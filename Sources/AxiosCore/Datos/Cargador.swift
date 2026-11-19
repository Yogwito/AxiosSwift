import Foundation

/// Tipo de archivo del manual o de señales. Se detecta por el contenido, no por el nombre.
public enum TipoArchivo: String {
    case lexico
    case reglas
    case senales
    case vocabEs = "vocab_es"
}

/// Línea del archivo que no se pudo cargar. `linea` cuenta desde 1 e incluye comentarios.
public struct ErrorLinea: Equatable {
    public var linea: Int
    public var contenido: String
    public var motivo: String

    public init(linea: Int, contenido: String, motivo: String) {
        self.linea = linea
        self.contenido = contenido
        self.motivo = motivo
    }
}

public struct ResultadoCarga: Equatable {
    public var tipo: TipoArchivo
    /// Filas nuevas en la BD (en el léxico, una por lengua) y correcciones aplicadas.
    public var nuevas: Int
    /// Filas que ya estaban vigentes y correcciones ya aplicadas.
    public var omitidas: Int
    public var errores: [ErrorLinea]
    public var cargaId: Int64

    public init(tipo: TipoArchivo, nuevas: Int, omitidas: Int, errores: [ErrorLinea], cargaId: Int64) {
        self.tipo = tipo
        self.nuevas = nuevas
        self.omitidas = omitidas
        self.errores = errores
        self.cargaId = cargaId
    }
}

/// Errores que impiden cargar el archivo completo. Los problemas de una sola
/// línea no lanzan: se devuelven en `ResultadoCarga.errores`.
public enum ErrorCarga: Error, Equatable {
    case archivoNoEncontrado(String)
    case noEsUTF8(String)
    case formatoDesconocido(String)
}

/// Problema de una línea concreta; se convierte en `ErrorLinea`.
private struct ProblemaLinea: Error {
    var motivo: String
    init(_ motivo: String) { self.motivo = motivo }
}

/// Resultado de procesar una línea válida.
private struct Conteo {
    var nuevas = 0
    var omitidas = 0

    mutating func sumar(_ insertada: Bool) {
        if insertada { nuevas += 1 } else { omitidas += 1 }
    }
}

extension BaseDatos {
    public func cargar(ruta: String) throws -> ResultadoCarga {
        try cargar(archivo: URL(fileURLWithPath: ruta))
    }

    /// Carga un archivo del manual (léxico, reglas, vocabulario) o de señales y
    /// correcciones. Todo ocurre en una transacción; una línea mal formada se
    /// reporta con su número y la carga sigue con las demás.
    public func cargar(archivo: URL) throws -> ResultadoCarga {
        let lineas = try leerLineas(archivo)
        let (tipo, version) = try detectarTipo(lineas, nombre: archivo.lastPathComponent)

        return try transaccion {
            let cargaId = try crearCarga(archivo: archivo.lastPathComponent, tipo: tipo.rawValue, version: version)
            var conteo = Conteo()
            var errores: [ErrorLinea] = []

            for (indice, linea) in lineas.enumerated() {
                let limpia = linea.trimmingCharacters(in: .whitespaces)
                if limpia.isEmpty || limpia.hasPrefix("#") { continue }

                let campos = limpia
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                do {
                    switch tipo {
                    case .lexico: try procesarLexico(campos, cargaId: cargaId, conteo: &conteo)
                    case .reglas: try procesarRegla(campos, cargaId: cargaId, conteo: &conteo)
                    case .vocabEs: try procesarVocab(campos, conteo: &conteo)
                    case .senales: try procesarSenalOCorreccion(campos, cargaId: cargaId, conteo: &conteo)
                    }
                } catch let problema as ProblemaLinea {
                    errores.append(ErrorLinea(linea: indice + 1, contenido: linea, motivo: problema.motivo))
                } catch let ErrorBD.sql(mensaje) {
                    errores.append(ErrorLinea(
                        linea: indice + 1, contenido: linea, motivo: "error de base de datos: \(mensaje)"
                    ))
                }
            }

            try cerrarCarga(
                id: cargaId,
                filas: conteo.nuevas,
                errores: errores.map { "línea \($0.linea): \($0.motivo)" }
            )
            return ResultadoCarga(
                tipo: tipo, nuevas: conteo.nuevas, omitidas: conteo.omitidas,
                errores: errores, cargaId: cargaId
            )
        }
    }

    // MARK: - Lectura y detección

    /// Lee el archivo como UTF-8, quita el BOM y el "\r" final de cada línea.
    private func leerLineas(_ archivo: URL) throws -> [String] {
        let datos: Data
        do {
            datos = try Data(contentsOf: archivo)
        } catch {
            throw ErrorCarga.archivoNoEncontrado(archivo.path)
        }
        guard var contenido = String(data: datos, encoding: .utf8) else {
            throw ErrorCarga.noEsUTF8(archivo.path)
        }
        if contenido.hasPrefix("\u{FEFF}") {
            contenido.removeFirst()
        }
        // "\r\n" es un solo Character en Swift: se parte por escalares para separar ambos.
        return contenido.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { escalares in
                var linea = String(String.UnicodeScalarView(escalares))
                if linea.hasSuffix("\r") { linea.removeLast() }
                return linea
            }
    }

    private func detectarTipo(_ lineas: [String], nombre: String) throws -> (TipoArchivo, String?) {
        let utiles = lineas.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let version = extraerVersion(utiles.filter { $0.hasPrefix("#") })

        if let primera = utiles.first {
            if primera.hasPrefix("#lexico") { return (.lexico, version) }
            if primera.hasPrefix("#reglas") { return (.reglas, version) }
            if primera.hasPrefix("#vocab_es") { return (.vocabEs, version) }
        }
        if utiles.contains(where: { $0.hasPrefix("SENAL|") || $0.hasPrefix("CORRECCION|") }) {
            return (.senales, version)
        }
        throw ErrorCarga.formatoDesconocido(nombre)
    }

    /// Versión del manual: lo que sigue a "version=" (cabecera) o a "versión " (comentario).
    private func extraerVersion(_ comentarios: [String]) -> String? {
        for linea in comentarios {
            for marca in ["version=", "versión "] {
                guard let rango = linea.range(of: marca) else { continue }
                let resto = linea[rango.upperBound...]
                let valor = resto.prefix { !$0.isWhitespace && $0 != "|" }
                if !valor.isEmpty { return String(valor) }
            }
        }
        return nil
    }

    // MARK: - Proceso por tipo

    private func exigirCampos(_ campos: [String], _ cantidad: Int, formato: String) throws {
        guard campos.count == cantidad else {
            throw ProblemaLinea("se esperaban \(cantidad) campos (\(formato)) y hay \(campos.count)")
        }
    }

    private func lenguaDestino(_ texto: String) throws -> Lengua {
        guard let lengua = Lengua(rawValue: texto.lowercased()), lengua != .es else {
            throw ProblemaLinea("lengua no válida: '\(texto)' (debe ser kethari u ozh)")
        }
        return lengua
    }

    private func procesarLexico(_ campos: [String], cargaId: Int64, conteo: inout Conteo) throws {
        try exigirCampos(campos, 4, formato: "es|kethari|ozh|categoria")
        let es = campos[0]
        guard !es.isEmpty else { throw ProblemaLinea("falta la palabra en español") }
        let categoria = campos[3].isEmpty ? nil : campos[3]

        let formas: [(Lengua, String)] = [(.kethari, campos[1]), (.ozh, campos[2])].filter { !$0.1.isEmpty }
        guard !formas.isEmpty else {
            throw ProblemaLinea("'\(es)' no tiene traducción en ninguna lengua")
        }
        for (lengua, forma) in formas {
            conteo.sumar(try insertarLexico(es: es, lengua: lengua, forma: forma, categoria: categoria, cargaId: cargaId))
        }
    }

    private func procesarRegla(_ campos: [String], cargaId: Int64, conteo: inout Conteo) throws {
        try exigirCampos(campos, 3, formato: "lengua|clave|valor")
        let lengua = try lenguaDestino(campos[0])
        guard !campos[1].isEmpty else { throw ProblemaLinea("falta la clave de la regla") }
        guard !campos[2].isEmpty else { throw ProblemaLinea("falta el valor de la regla '\(campos[1])'") }
        conteo.sumar(try insertarRegla(lengua: lengua, clave: campos[1], valor: campos[2], cargaId: cargaId))
    }

    private func procesarVocab(_ campos: [String], conteo: inout Conteo) throws {
        try exigirCampos(campos, 4, formato: "forma|lema|categoria|rasgos")
        guard !campos[0].isEmpty else { throw ProblemaLinea("falta la forma") }
        func opcional(_ s: String) -> String? { s.isEmpty ? nil : s }
        conteo.sumar(try insertarVocab(
            forma: campos[0], lema: opcional(campos[1]), categoria: opcional(campos[2]), rasgos: opcional(campos[3])
        ))
    }

    private func procesarSenalOCorreccion(_ campos: [String], cargaId: Int64, conteo: inout Conteo) throws {
        switch campos[0] {
        case "SENAL":
            try exigirCampos(campos, 5, formato: "SENAL|dia|voz|transcripcion|salida")
            guard let dia = Int(campos[1]), dia > 0 else {
                throw ProblemaLinea("día no válido: '\(campos[1])' (debe ser un entero mayor que 0)")
            }
            let voz = campos[2].lowercased()
            guard !voz.isEmpty else { throw ProblemaLinea("falta la voz de la señal") }
            let salida = campos[4].isEmpty ? nil : campos[4]
            conteo.sumar(try insertarSenal(
                dia: dia, voz: voz, transcripcion: campos[3], salida: salida, cargaId: cargaId
            ))

        case "CORRECCION":
            try exigirCampos(campos, 5, formato: "CORRECCION|lengua|palabra|anterior|nuevo")
            let lengua = try lenguaDestino(campos[1])
            let (palabra, anterior, nuevo) = (campos[2], campos[3], campos[4])
            guard !palabra.isEmpty, !anterior.isEmpty, !nuevo.isEmpty else {
                throw ProblemaLinea("la corrección necesita palabra, significado anterior y nuevo")
            }
            switch try corregirSignificado(
                lengua: lengua, forma: palabra, anterior: anterior, nuevo: nuevo, cargaId: cargaId
            ) {
            case .aplicada: conteo.nuevas += 1
            case .yaAplicada: conteo.omitidas += 1
            case .noEncontrada:
                throw ProblemaLinea("no se encontró '\(palabra)' = '\(anterior)' vigente en \(lengua.rawValue)")
            }

        default:
            throw ProblemaLinea("línea no reconocida: se esperaba SENAL|... o CORRECCION|...")
        }
    }
}
