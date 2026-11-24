// Retrotraducción (P1, bonus): lee una frase en Kethari u Ozh con los validadores
// de P4 y la devuelve al español como glosa, con los significados vigentes en una
// fecha. Lo que el validador no acepta no se retrotraduce.

import Foundation

public struct Retrotraduccion: Equatable {
    /// "¿cuándo · ustedes · llegar/venir [futuro]?"
    public var texto: String
    /// La estructura que dio el validador: "[INT kom] [S ulesh] [V vinime] [PREG]".
    public var estructura: String
}

public struct ErrorRetrotraduccion: Error, Equatable {
    public var motivo: String
    public var columna: Int?
}

public struct Retrotraductor {
    let bd: BaseDatos

    public init(bd: BaseDatos) {
        self.bd = bd
    }

    /// Con `fecha`, usa lo que significaba cada palabra en ese momento; sin ella, lo vigente.
    public func retrotraducir(_ frase: String, desde lengua: Lengua, en fecha: Date? = nil)
        -> Result<Retrotraduccion, ErrorRetrotraduccion> {
        let validacion: ResultadoValidacion
        switch lengua {
        case .kethari: validacion = validarKethari(frase, lexicon: bd)
        case .ozh: validacion = validarOzh(frase, lexicon: bd)
        case .es: return .failure(ErrorRetrotraduccion(motivo: "solo se retrotraduce desde Kethari u Ozh", columna: nil))
        }
        guard validacion.valida, let estructura = validacion.estructura else {
            return .failure(ErrorRetrotraduccion(motivo: validacion.motivo ?? "frase no válida", columna: validacion.columna))
        }
        let lector = Lector(bd: bd, lengua: lengua, fecha: fecha)
        return .success(Retrotraduccion(texto: lector.glosa(Retrotraductor.partes(estructura)), estructura: estructura))
    }

    /// "[S ir] [O thüm ʔenka] [PREG]" → [("S", ["ir"]), ("O", ["thüm", "ʔenka"]), ("PREG", [])]
    static func partes(_ estructura: String) -> [(etiqueta: String, palabras: [String])] {
        var resultado: [(etiqueta: String, palabras: [String])] = []
        var actual: String?
        for c in estructura {
            if c == "[" {
                actual = ""
            } else if c == "]" {
                let piezas = (actual ?? "").split(separator: " ").map(String.init)
                if let etiqueta = piezas.first {
                    resultado.append((etiqueta, Array(piezas.dropFirst())))
                }
                actual = nil
            } else if actual != nil {
                actual?.append(c)
            }
        }
        return resultado
    }
}

/// Glosa de una frase de una lengua, a partir de las partes del validador.
private struct Lector {
    let bd: BaseDatos
    let lengua: Lengua
    let fecha: Date?
    let cifras: Cifras

    init(bd: BaseDatos, lengua: Lengua, fecha: Date?) {
        self.bd = bd
        self.lengua = lengua
        self.fecha = fecha
        cifras = Cifras(lexicon: bd, lengua: lengua)
    }

    /// Etiquetas de la estructura de los validadores de P4.
    enum Etiqueta {
        static let interrogativo = "INT", sujeto = "S", objeto = "O", verbo = "V"
        static let negacion = "NEG", tiempo = "T", particula = "P", pregunta = "PREG"
    }

    func glosa(_ partes: [(etiqueta: String, palabras: [String])]) -> String {
        var interrogativo: String?
        var sujeto: String?
        var objetos: [String] = []
        var verbo: (raiz: String, negativa: Bool, tiempo: Tiempo?, pregunta: Bool)?
        var negativa = false
        var tiempo: Tiempo?
        var pregunta = false
        var particula: String?

        for (etiqueta, palabras) in partes {
            switch etiqueta {
            case Etiqueta.interrogativo: interrogativo = palabras.map(significado).joined(separator: " ")
            case Etiqueta.sujeto: sujeto = sintagma(palabras)
            case Etiqueta.objeto: objetos.append(sintagma(palabras))
            case Etiqueta.verbo: verbo = palabras.first.map(analizarVerbo)
            case Etiqueta.negacion: negativa = true
            case Etiqueta.tiempo: tiempo = palabras.first.flatMap(marcaDeTiempo)
            case Etiqueta.particula: particula = palabras.first
            case Etiqueta.pregunta: pregunta = true
            default: break
            }
        }

        var textoVerbo: String?
        if let verbo {
            let t = tiempo ?? verbo.tiempo
            textoVerbo = (negativa || verbo.negativa ? "no " : "") + significado(verbo.raiz)
                + (t.map { " [\($0.rawValue)]" } ?? "")
            pregunta = pregunta || verbo.pregunta
        }

        var texto = ([interrogativo, sujeto, textoVerbo].compactMap { $0 } + objetos).joined(separator: " · ")
        if let particula { texto += " [\(particula)]" }
        return pregunta || interrogativo != nil ? "¿\(texto)?" : texto
    }

    private func regla(_ clave: String) -> String? {
        guard let v = bd.regla(clave, lengua: lengua), !v.isEmpty else { return nil }
        return v
    }

    private func categoria(_ forma: String) -> String? {
        bd.categoria(forma: forma, lengua: lengua)
    }

    /// Los significados de la forma en la fecha, separados por "/", o "[forma]" si no hay.
    func significado(_ forma: String) -> String {
        let s = bd.significados(forma: forma, lengua: lengua, en: fecha)
        return s.isEmpty ? "[\(forma)]" : s.joined(separator: "/")
    }

    /// Número, nombre (con plural) y poseedor: "15 nave", "mundo de nosotros".
    func sintagma(_ palabras: [String]) -> String {
        var cantidad: Int?
        var nombre: (raiz: String, plural: Bool)?
        var otras: [String] = []
        for w in palabras {
            if categoria(w) == Categoria.pronombre {
                otras.append(significado(w))
            } else if let n = analizarNombre(w) {
                nombre = n
            } else if cifras.pareceNumero(w),
                      let v = try? cifras.valor(de: Token(tipo: .palabra, texto: w, linea: 1, columna: 1)) {
                cantidad = v
            } else {
                otras.append(significado(w))
            }
        }
        guard let nombre else { return otras.joined(separator: " ") }
        var texto = significado(nombre.raiz)
        if let cantidad {
            texto = "\(cantidad) " + texto
        } else if nombre.plural {
            texto += " [plural]"
        }
        // Un pronombre junto a un nombre es su poseedor, vaya antes (Kethari) o después (Ozh).
        if !otras.isEmpty {
            texto += " de " + otras.joined(separator: " ")
        }
        return texto
    }

    /// La raíz de un nombre y si lleva el sufijo de plural.
    func analizarNombre(_ w: String) -> (raiz: String, plural: Bool)? {
        if categoria(w) == Categoria.sustantivo { return (w, false) }
        if let sufijo = regla("sufijo_plural"), w.hasSuffix(sufijo) {
            let raiz = String(w.dropLast(sufijo.count))
            if categoria(raiz) == Categoria.sustantivo { return (raiz, true) }
        }
        return nil
    }

    /// Raíz del verbo y lo que marcan sus afijos: negación y tiempo (Kethari), pregunta (Ozh).
    func analizarVerbo(_ w: String) -> (raiz: String, negativa: Bool, tiempo: Tiempo?, pregunta: Bool) {
        var formas: [(forma: String, negativa: Bool, pregunta: Bool)] = [(w, false, false)]
        if let prefijo = regla("prefijo_negacion"), w.hasPrefix(prefijo) {
            formas.append((String(w.dropFirst(prefijo.count)), true, false))
        }
        if let prefijo = regla("prefijo_pregunta"), w.hasPrefix(prefijo) {
            formas.append((String(w.dropFirst(prefijo.count)), false, true))
        }
        let sufijos: [(String, Tiempo)] = [("sufijo_pasado", .pasado), ("sufijo_futuro", .futuro)]
        for f in formas {
            if categoria(f.forma) == Categoria.verbo { return (f.forma, f.negativa, nil, f.pregunta) }
            for (clave, t) in sufijos {
                guard let sufijo = regla(clave), f.forma.hasSuffix(sufijo) else { continue }
                let raiz = String(f.forma.dropLast(sufijo.count))
                if categoria(raiz) == Categoria.verbo { return (raiz, f.negativa, t, f.pregunta) }
            }
        }
        return (w, false, nil, false)
    }

    /// Ozh: la marca del principio de la oración ("ʔoka" pasado, "venu" futuro).
    func marcaDeTiempo(_ w: String) -> Tiempo? {
        if w == regla("marca_pasado") { return .pasado }
        if w == regla("marca_futuro") { return .futuro }
        return nil
    }
}
