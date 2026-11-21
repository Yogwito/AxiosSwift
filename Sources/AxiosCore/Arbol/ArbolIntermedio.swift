// Árbol intermedio: lo que produce el analizador sintáctico (P2) y consumen los
// generadores de Kethari y Ozh (P3). Describe la oración en términos del español
// (lemas, persona, número, tiempo) y no sabe nada de las lenguas destino: el orden
// de las palabras, los afijos y las partículas los decide cada generador con las
// reglas de la BD. El contrato completo está en docs/contrato-arbol.md.

import Foundation

// MARK: - Oración

/// Tipo de oración. La pregunta parcial lleva su palabra interrogativa, así no
/// puede existir una pregunta parcial sin interrogativo ni una declarativa con él.
public enum TipoOracion: Equatable {
    /// "Queremos paz."
    case declarativa
    /// "¿Vienen ustedes?" (se contesta con sí o no)
    case preguntaSiNo
    /// "¿Cuándo llegan?" (pregunta por un dato)
    case preguntaParcial(Interrogativo)
}

/// Raíz del árbol: una oración simple con un solo verbo.
public struct Oracion: Equatable {
    public var tipo: TipoOracion
    public var sujeto: Sujeto
    public var verbo: NodoVerbo
    /// Complemento directo ("paz" en "Queremos paz"), o nil si no hay.
    public var objeto: SN?

    public init(tipo: TipoOracion, sujeto: Sujeto, verbo: NodoVerbo, objeto: SN? = nil) {
        self.tipo = tipo
        self.sujeto = sujeto
        self.verbo = verbo
        self.objeto = objeto
    }

    /// Palabra interrogativa de la oración, si es una pregunta parcial.
    public var interrogativo: Interrogativo? {
        if case .preguntaParcial(let i) = tipo { return i }
        return nil
    }

    /// Una línea legible para la traza, por ejemplo
    /// `parcial(cuando, circunstancial) · S: omitido · V: llegar 3pl presente · O: —`.
    public func texto() -> String {
        let tipoTexto: String
        switch tipo {
        case .declarativa: tipoTexto = "declarativa"
        case .preguntaSiNo: tipoTexto = "pregunta sí/no"
        case .preguntaParcial(let i): tipoTexto = "parcial(\(i.lema), \(i.funcion.rawValue))"
        }
        return [
            tipoTexto,
            "S: \(sujeto.texto())",
            "V: \(verbo.texto())",
            "O: \(objeto?.texto() ?? "—")",
        ].joined(separator: " · ")
    }
}

// MARK: - Sujeto

public enum Sujeto: Equatable {
    /// El sujeto está escrito en la frase: "Ustedes vienen", "Quince naves llegaron".
    case explicito(SN)
    /// No está escrito ("¿Cuándo llegan?"): su persona y número son los del verbo
    /// (`NodoVerbo.rasgos`). Kethari y Ozh exigen sujeto, así que P3 lo repone.
    case omitido
    /// El sujeto es la propia palabra interrogativa: "¿Quién envió el mensaje?".
    case interrogativo

    func texto() -> String {
        switch self {
        case .explicito(let sn): return sn.texto()
        case .omitido: return "omitido"
        case .interrogativo: return "interrogativo"
        }
    }
}

// MARK: - Sintagma nominal

/// Pronombre personal o posesivo reducido a lo que necesitan los generadores.
public struct Pronombre: Equatable {
    /// Clave del pronombre personal en el léxico (`es_clave`): "nosotros", "el", "ustedes".
    /// En un posesivo es el pronombre del poseedor: "nuestro" → "nosotros".
    public var lema: String
    /// 1, 2 o 3.
    public var persona: Int
    public var plural: Bool

    public init(lema: String, persona: Int, plural: Bool) {
        self.lema = lema
        self.persona = persona
        self.plural = plural
    }

    /// Primera persona plural: el árbol solo la marca y P3 decide la forma
    /// incluyente o excluyente de cada lengua (bitácora 2026-11-21).
    public var esPrimeraPlural: Bool { persona == 1 && plural }
}

/// Núcleo del sintagma nominal.
public enum Nucleo: Equatable {
    case pronombre(Pronombre)
    /// Sustantivo por su lema en singular ("nave" para "naves") y su número.
    case sustantivo(lema: String, plural: Bool)
}

/// Sintagma nominal: "su planeta", "quince naves", "nosotros".
/// Los artículos ("el", "un") no se guardan: Kethari y Ozh no tienen.
public struct SN: Equatable {
    public var nucleo: Nucleo
    /// Cantidad ya convertida a número ("quince naves" → 15), o nil si no hay.
    public var cantidad: Int?
    /// Poseedor ("nuestro mundo" → nosotros), o nil si no hay.
    public var poseedor: Pronombre?

    public init(nucleo: Nucleo, cantidad: Int? = nil, poseedor: Pronombre? = nil) {
        self.nucleo = nucleo
        self.cantidad = cantidad
        self.poseedor = poseedor
    }

    /// Número gramatical del sintagma.
    public var plural: Bool {
        switch nucleo {
        case .pronombre(let p): return p.plural
        case .sustantivo(_, let plural): return plural
        }
    }

    func texto() -> String {
        var partes: [String] = []
        if let cantidad { partes.append(String(cantidad)) }
        switch nucleo {
        case .pronombre(let p): partes.append("pron(\(p.lema))")
        case .sustantivo(let lema, let plural): partes.append(plural ? "\(lema)+pl" : lema)
        }
        if let poseedor { partes.append("de(\(poseedor.lema))") }
        return partes.joined(separator: " ")
    }
}

// MARK: - Verbo

public enum Polaridad: String, Equatable {
    case afirmativa
    case negativa
}

/// Verbo de la oración. `rasgos.raiz` es el infinitivo del verbo que se traduce:
/// en "van a llegar" es "llegar" (no "ir"), con el tiempo `.futuro`.
public struct NodoVerbo: Equatable {
    /// Infinitivo, persona, número y tiempo (contrato `RasgosVerbo` de Modelos.swift).
    public var rasgos: RasgosVerbo
    public var polaridad: Polaridad
    /// true si el futuro vino de "ir a + infinitivo". Es solo informativo: el tiempo
    /// ya es `.futuro` y los generadores no necesitan mirarlo.
    public var perifrastico: Bool

    public init(rasgos: RasgosVerbo, polaridad: Polaridad = .afirmativa, perifrastico: Bool = false) {
        self.rasgos = rasgos
        self.polaridad = polaridad
        self.perifrastico = perifrastico
    }

    public var negado: Bool { polaridad == .negativa }

    func texto() -> String {
        var partes = [
            rasgos.raiz,
            "\(rasgos.persona)\(rasgos.plural ? "pl" : "sg")",
            rasgos.tiempo.rawValue,
        ]
        if perifrastico { partes.append("(ir a)") }
        if negado { partes.append("negativa") }
        return partes.joined(separator: " ")
    }
}

// MARK: - Interrogativo

/// Qué parte de la oración pregunta el interrogativo.
public enum FuncionInterrogativo: String, Equatable {
    /// "¿Quién envió el mensaje?", "¿Cuántas naves llegaron?"
    case sujeto
    /// "¿Qué quieren?", "¿Cuántos ciclos esperarán?"
    case objeto
    /// "¿Cuándo llegan?", "¿Dónde están?"
    case circunstancial
}

/// Palabra interrogativa de una pregunta parcial.
public struct Interrogativo: Equatable {
    /// Clave en el léxico, sin tilde: "que", "cuando", "donde", "cuantos", "quien".
    public var lema: String
    public var funcion: FuncionInterrogativo

    public init(lema: String, funcion: FuncionInterrogativo) {
        self.lema = lema
        self.funcion = funcion
    }
}
