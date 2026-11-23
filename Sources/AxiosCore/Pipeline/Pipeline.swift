// Aquí se junta todo: la pregunta pasa por cada fase en orden y cada una deja su
// resultado en la traza. Pase lo que pase, siempre se devuelve un registro, ya sea
// con las traducciones o con la razón por la que no se pudo traducir.

import Foundation

public enum Pipeline {
    /// Cómo se llaman nuestras fases en la traza. Las del analizador sintáctico
    /// las pone P2 (`AnalizadorSintactico.Fase`).
    public enum Fase {
        public static let normalizacion = "normalizacion"
        public static let lexico = "lexico"
        public static let correccion = "correccion"
        public static let kethari = "kethari"
        public static let ozh = "ozh"
        public static let validacion = "validacion"
        public static let retrotraduccion = "retrotraduccion"
    }

    /// Traduce una pregunta de principio a fin. Tiene la misma forma que espera la
    /// CLI, así que basta con pasársela: `CLI(bd:traductor: Pipeline.traducir, ...)`.
    public static func traducir(_ pregunta: String, bd: BaseDatos, traza: inout Traza) -> RegistroPregunta {
        var registro = RegistroPregunta(fecha: bd.reloj(), original: pregunta)

        // Limpiamos la pregunta y pasamos los números en letras a cifras.
        let normalizado = Normalizador(lexicon: bd).normalizar(pregunta)
        registro.normalizada = normalizado.texto
        traza.agregar(fase: Fase.normalizacion, salida: normalizado.texto)

        // La partimos en tokens. Si hay un carácter raro, paramos aquí.
        let tokens: [Token]
        switch AnalizadorLexico.analizar(normalizado) {
        case .success(let t):
            tokens = t
            traza.agregar(fase: Fase.lexico, salida: AnalizadorLexico.texto(t))
        case .failure(let error):
            traza.agregar(fase: Fase.lexico, salida: "error · \(error.texto())")
            registro.motivo = "error léxico: \(error.texto())"
            return registro
        }

        // Arreglamos las palabras mal escritas.
        let corregido = Corrector(lexicon: bd).corregir(tokens)
        registro.correcciones = corregido.correcciones
        traza.agregar(fase: Fase.correccion, salida: Corrector.texto(corregido.correcciones))

        // El analizador de P2 arma el árbol y anota sus propias fases en la traza.
        let oracion: Oracion
        switch AnalizadorSintactico(lexicon: bd).analizar(corregido.tokens, traza: &traza) {
        case .success(let o):
            oracion = o
        case .failure(let error):
            registro.motivo = "error sintáctico: \(error.texto())"
            return registro
        }

        // Los generadores de P3 escriben la frase en cada lengua. Si a una le falta
        // alguna palabra, esa lengua se queda sin traducción: no inventamos nada.
        var motivos: [String] = []
        let kethari = generar(oracion, en: .kethari, bd: bd, traza: &traza, motivos: &motivos)
        let ozh = generar(oracion, en: .ozh, bd: bd, traza: &traza, motivos: &motivos)
        registro.kethari = kethari
        registro.ozh = ozh

        // Antes de aprobar, los validadores de P4 vuelven a leer cada traducción.
        // Lo que aprueban lo retrotraducimos para ver en español qué se va a enviar.
        var validaciones: [String] = []
        var retro: [String] = []
        for (lengua, texto) in [(Lengua.kethari, kethari), (Lengua.ozh, ozh)] {
            guard let texto else { continue }
            let r = lengua == .kethari ? validarKethari(texto, lexicon: bd) : validarOzh(texto, lexicon: bd)
            if lengua == .kethari { registro.validaK = r.valida } else { registro.validaO = r.valida }
            if r.valida {
                validaciones.append("\(lengua.rawValue): válida \(r.estructura ?? "")")
                if case .success(let rt) = Retrotraductor(bd: bd).retrotraducir(texto, desde: lengua) {
                    retro.append("\(lengua == .kethari ? "K" : "O"): \(rt.texto)")
                }
            } else {
                let donde = r.columna.map { " (columna \($0))" } ?? ""
                validaciones.append("\(lengua.rawValue): inválida\(donde): \(r.motivo ?? "")")
                motivos.append("\(lengua.nombre) rechazada por el validador\(donde): \(r.motivo ?? "")")
            }
        }
        if !validaciones.isEmpty {
            traza.agregar(fase: Fase.validacion, salida: validaciones.joined(separator: " | "))
        }
        if !retro.isEmpty {
            traza.agregar(fase: Fase.retrotraduccion, salida: retro.joined(separator: " | "))
        }

        registro.motivo = motivos.isEmpty ? nil : motivos.joined(separator: "; ")
        return registro
    }

    /// Pide la frase al generador de esa lengua. Si no se puede, devuelve nil y
    /// anota el porqué en `motivos`.
    private static func generar(
        _ oracion: Oracion, en lengua: Lengua, bd: BaseDatos, traza: inout Traza, motivos: inout [String]
    ) -> String? {
        let fase = lengua == .kethari ? Fase.kethari : Fase.ozh
        do {
            let t = lengua == .kethari
                ? try GeneradorKethari(lexicon: bd).traducir(oracion)
                : try GeneradorOzh(lexicon: bd).traducir(oracion)
            guard t.completa else {
                let porque = t.sinRespaldo.map(\.explicacion).joined(separator: "; ")
                traza.agregar(fase: fase, salida: "\(t.texto) · sin respaldo: \(porque)")
                motivos.append("\(lengua.nombre) sin traducción: \(porque)")
                return nil
            }
            traza.agregar(fase: fase, salida: t.texto)
            return t.texto
        } catch {
            let porque = describir(error)
            traza.agregar(fase: fase, salida: "error · \(porque)")
            motivos.append("\(lengua.nombre) sin traducción: \(porque)")
            return nil
        }
    }

    /// Explica en palabras un error del generador.
    private static func describir(_ error: Error) -> String {
        switch error {
        case ErrorGeneracion.sinTraduccion(let lema, _): return "'\(lema)' no tiene traducción"
        case ErrorGeneracion.faltaRegla(let clave, _): return "falta la regla '\(clave)'"
        default: return "\(error)"
        }
    }
}
