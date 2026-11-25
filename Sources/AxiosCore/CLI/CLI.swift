import Foundation

/// Órdenes de la línea de comandos. No imprime: devuelve el texto a mostrar,
/// así se puede probar sin capturar la salida estándar.
public struct CLI {
    public typealias Traductor = (String, BaseDatos, inout Traza) -> RegistroPregunta

    public static let ayuda = """
        Traductor Axios
        Órdenes:
          traducir "<pregunta>" [--traza]  traduce a Kethari y Ozh (--traza muestra cada fase)
          cargar <archivo>                 carga léxico, reglas, señales o correcciones del manual
          inicializar                      carga el léxico, las reglas y las señales de la semana 1
          historial [desde AAAA-MM-DD]     lista lo que se tradujo
          palabra <término>                muestra una palabra en las tres lenguas
          validar <kethari|ozh> "<frase>"  comprueba si una frase es correcta en esa lengua
        """

    /// Archivos que carga `inicializar`, en orden. La semana 2 se carga aparte con `cargar`.
    static let archivosIniciales = [
        "lexico_v0.7.txt", "reglas_v0.7.txt", "vocab_es_v0.7.txt", "numeros_es_v0.7.txt",
        "senales_semana1.txt",
    ]

    private let bd: BaseDatos
    private let traductor: Traductor?
    private let raizDatos: URL
    private let formatoDia: DateFormatter
    private let formatoMinuto: DateFormatter

    /// - Parameter zonaHoraria: zona en la que se leen y muestran las fechas
    ///   (la local por defecto; los tests usan una fija para no depender de la máquina).
    public init(
        bd: BaseDatos, traductor: Traductor? = nil, raizDatos: URL,
        zonaHoraria: TimeZone = .current
    ) {
        self.bd = bd
        self.traductor = traductor
        self.raizDatos = raizDatos
        formatoDia = CLI.formateador("yyyy-MM-dd", zonaHoraria)
        formatoMinuto = CLI.formateador("yyyy-MM-dd HH:mm", zonaHoraria)
    }

    public func ejecutar(_ args: [String]) -> String {
        guard let orden = args.first else { return CLI.ayuda }
        let resto = Array(args.dropFirst())
        switch orden {
        case "traducir": return traducir(resto)
        case "cargar": return cargar(resto)
        case "inicializar": return inicializar()
        case "historial": return historial(resto)
        case "palabra": return palabra(resto)
        case "validar": return validar(resto)
        case "ayuda", "-h", "--help": return CLI.ayuda
        default: return "Orden desconocida: '\(orden)'\n\n" + CLI.ayuda
        }
    }

    // MARK: - traducir

    private func traducir(_ args: [String]) -> String {
        let conTraza = args.contains("--traza")
        let pregunta = args.filter { $0 != "--traza" }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var traza = Traza()
        traza.agregar(fase: "entrada", salida: pregunta)

        var registro: RegistroPregunta
        if pregunta.isEmpty {
            registro = RegistroPregunta(fecha: bd.reloj(), original: pregunta, motivo: "pregunta vacía")
        } else if let traductor {
            registro = traductor(pregunta, bd, &traza)
        } else {
            registro = RegistroPregunta(
                fecha: bd.reloj(), original: pregunta, motivo: "traductor no integrado todavía"
            )
        }
        if registro.traza == nil {
            registro.traza = traza.texto()
        }

        var lineas: [String] = []
        if conTraza {
            lineas += traza.fases.map { "[\($0.nombre)] \($0.salida)" }
            lineas.append("")
        }
        // Las correcciones se muestran siempre: quien pregunta debe saber qué se tradujo en realidad.
        if !registro.correcciones.isEmpty {
            let cambios = registro.correcciones.map { "\($0.original) → \($0.corregida)" }
            lineas.append("Corregido: \(cambios.joined(separator: ", "))")
        }
        lineas.append("Kethari: \(CLI.resultado(registro.kethari, valida: registro.validaK))")
        lineas.append("Ozh:     \(CLI.resultado(registro.ozh, valida: registro.validaO))")
        if let motivo = registro.motivo {
            lineas.append("Motivo:  \(motivo)")
        }

        do {
            let id = try bd.registrar(registro)
            lineas.append("Registrada como #\(id)")
        } catch {
            lineas.append("Error: no se pudo registrar la pregunta (\(describir(error)))")
        }
        return lineas.joined(separator: "\n")
    }

    /// Texto de una lengua con su etiqueta: sin traducción, válida o rechazada por el validador.
    static func resultado(_ texto: String?, valida: Bool) -> String {
        guard let texto, !texto.isEmpty else { return "—   [sin traducción]" }
        return "\(texto)   [\(valida ? "válida" : "rechazada por el validador")]"
    }

    // MARK: - cargar / inicializar

    private func cargar(_ args: [String]) -> String {
        guard args.count == 1 else { return "Uso: cargar <archivo>" }
        return cargarArchivo(URL(fileURLWithPath: args[0]))
    }

    private func inicializar() -> String {
        CLI.archivosIniciales
            .map { cargarArchivo(raizDatos.appendingPathComponent($0)) }
            .joined(separator: "\n\n")
    }

    private func cargarArchivo(_ url: URL) -> String {
        do {
            let r = try bd.cargar(archivo: url)
            var lineas = [
                "Archivo: \(url.lastPathComponent)",
                "  tipo: \(r.tipo.rawValue)",
                "  versión: \(r.version ?? "—")",
                "  nuevas: \(r.nuevas)",
                "  omitidas: \(r.omitidas)",
                "  errores: \(r.errores.count)",
            ]
            lineas += r.errores.map { "  línea \($0.linea): \($0.motivo)" }
            return lineas.joined(separator: "\n")
        } catch {
            return "Error al cargar \(url.lastPathComponent): \(describir(error))"
        }
    }

    // MARK: - historial

    private func historial(_ args: [String]) -> String {
        var desde: Date?
        switch args.count {
        case 0:
            break
        case 2 where args[0] == "desde":
            guard let fecha = formatoDia.date(from: args[1]) else {
                return "Fecha no válida: '\(args[1])'. Use el formato AAAA-MM-DD, por ejemplo 2026-11-01."
            }
            desde = fecha
        default:
            return "Uso: historial [desde AAAA-MM-DD]"
        }

        let preguntas = bd.preguntas(desde: desde)
        guard !preguntas.isEmpty else { return "No hay preguntas registradas." }

        return preguntas.map { p in
            let id = p.id.map { "#\($0)" } ?? "#?"
            var linea = "\(id)  \(formatoMinuto.string(from: p.fecha))  \(p.original)"
                + "  →  K: \(p.kethari ?? "—") | O: \(p.ozh ?? "—")"
            if let motivo = p.motivo { linea += "  [\(motivo)]" }
            return linea
        }.joined(separator: "\n")
    }

    // MARK: - validar

    private func validar(_ args: [String]) -> String {
        let uso = "Uso: validar <kethari|ozh> \"<frase>\""
        guard let primero = args.first, let lengua = Lengua(rawValue: primero.lowercased()), lengua != .es else {
            return uso
        }
        let frase = args.dropFirst().joined(separator: " ")
        let r = lengua == .kethari ? validarKethari(frase, lexicon: bd) : validarOzh(frase, lexicon: bd)
        if r.valida {
            return "válida: \(r.estructura ?? "")"
        }
        let donde = r.columna.map { " (columna \($0))" } ?? ""
        return "inválida\(donde): \(r.motivo ?? "sin motivo")"
    }

    // MARK: - palabra

    private func palabra(_ args: [String]) -> String {
        let termino = args.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !termino.isEmpty else { return "Uso: palabra <término>" }

        let filas = bd.historialPalabra(termino)
        let senales = senalesRelacionadas(termino, filas: filas)
        guard !filas.isEmpty || !senales.isEmpty else {
            return "No se sabe nada de '\(termino)': no está en el léxico ni aparece en las señales."
        }

        var lineas = ["Palabra: \(termino)"]

        // Lo vigente: cada significado español actual con su forma en cada lengua.
        var significados: [String] = []
        for fila in filas where fila.vigenteHasta == nil && !significados.contains(fila.es) {
            significados.append(fila.es)
        }
        lineas.append("")
        lineas.append("Vigente:")
        if significados.isEmpty {
            lineas.append("  (ningún significado vigente)")
        }
        for es in significados {
            let k = bd.traduccion(es: es, lengua: .kethari, en: nil) ?? "—"
            let o = bd.traduccion(es: es, lengua: .ozh, en: nil) ?? "—"
            lineas.append("  español: \(es)  ·  kethari: \(k)  ·  ozh: \(o)")
        }

        if !filas.isEmpty {
            lineas.append("")
            lineas.append("Versiones:")
            for fila in filas {
                let desde = formatoDia.string(from: fila.vigenteDesde)
                let hasta = fila.vigenteHasta.map { formatoDia.string(from: $0) } ?? "vigente"
                let archivo = fila.archivo.map { "  (\($0))" } ?? ""
                lineas.append("  \(fila.lengua.rawValue): \(fila.forma) = \(fila.es)  [\(desde) → \(hasta)]\(archivo)")
            }
        }

        lineas.append("")
        if senales.isEmpty {
            lineas.append("Señales: no aparece en ninguna señal.")
        } else {
            lineas.append("Señales:")
            for s in senales {
                lineas.append("  día \(s.dia) \(s.voz): \(s.transcripcion)")
            }
        }
        return lineas.joined(separator: "\n")
    }

    /// Señales donde aparece el término o alguna de sus formas del léxico, con las
    /// variantes (sufijos y negación) que dan las reglas de cada lengua.
    private func senalesRelacionadas(_ termino: String, filas: [BaseDatos.FilaLexico]) -> [BaseDatos.Senal] {
        var pares: [(forma: String, lengua: Lengua)] = [(termino, .kethari), (termino, .ozh)]
        for fila in filas where !pares.contains(where: { $0.forma == fila.forma && $0.lengua == fila.lengua }) {
            pares.append((fila.forma, fila.lengua))
        }
        var vistas = Set<Int64>()
        var resultado: [BaseDatos.Senal] = []
        for par in pares {
            for senal in bd.senales(conForma: par.forma, lengua: par.lengua) where vistas.insert(senal.id).inserted {
                resultado.append(senal)
            }
        }
        return resultado.sorted { ($0.dia, $0.id) < ($1.dia, $1.id) }
    }

    // MARK: - Utilidades

    private static func formateador(_ formato: String, _ zona: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zona
        f.dateFormat = formato
        f.isLenient = false
        return f
    }

    private func describir(_ error: Error) -> String {
        switch error {
        case ErrorCarga.archivoNoEncontrado(let ruta): return "no se encontró el archivo \(ruta)"
        case ErrorCarga.noEsUTF8(let ruta): return "el archivo \(ruta) no está en UTF-8"
        case ErrorCarga.formatoDesconocido(let nombre):
            return "no se reconoce el formato de \(nombre) (se esperaba #lexico, #reglas, #vocab_es o líneas SENAL|/CORRECCION|)"
        case ErrorBD.sql(let m), ErrorBD.apertura(let m), ErrorBD.esquema(let m): return m
        default: return "\(error)"
        }
    }
}
