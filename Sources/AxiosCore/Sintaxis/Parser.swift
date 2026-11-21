// Estado del analizador descendente recursivo: los tokens, la clase de cada uno y la
// posición actual. Cada no terminal de la BNF es un método con su mismo nombre, en
// Sintagmas.swift (sn, determinante, nominal, sv, verbo) y Oracion.swift (entrada,
// clausula, sintInterrog, nucleo). No hay retroceso: cada decisión mira el token
// actual y, solo en R12, el siguiente.

import Foundation

final class Parser {
    let tokens: [Token]
    let clases: [ClaseToken]
    let clasificador: Clasificador
    private(set) var posicion = 0
    /// No terminales visitados, en orden, con el token donde empezó cada uno:
    /// "entrada[¿]", "clausula[cuando]"... Es la derivación que muestra la traza.
    private(set) var recorrido: [String] = []

    /// Un sustantivo o un interrogativo concuerdan con el verbo en 3.ª persona (R3).
    static let personaNominal = 3

    init(tokens entrada: [Token], lexicon: Lexicon) {
        var tokens = entrada
        // La gramática termina en FIN: si el analizador léxico no lo puso, se agrega.
        if tokens.last?.tipo != .fin {
            let ultimo = tokens.last
            let columna = ultimo.map { $0.columna + $0.texto.count } ?? 1
            tokens.append(Token(tipo: .fin, texto: "", linea: ultimo?.linea ?? 1, columna: columna))
        }
        let clasificador = Clasificador(lexicon: lexicon)
        self.tokens = tokens
        self.clases = tokens.map(clasificador.clasificar)
        self.clasificador = clasificador
    }

    // MARK: - Cursor

    var actual: Token { tokens[posicion] }
    var claseActual: ClaseToken { clases[posicion] }

    /// Clase del token `desplazamiento` posiciones más adelante (FIN si se pasa).
    func clase(en desplazamiento: Int) -> ClaseToken {
        clases[min(posicion + desplazamiento, clases.count - 1)]
    }

    func token(en desplazamiento: Int) -> Token {
        tokens[min(posicion + desplazamiento, tokens.count - 1)]
    }

    @discardableResult
    func avanzar() -> Token {
        let token = actual
        if posicion < tokens.count - 1 { posicion += 1 }
        return token
    }

    /// Cada no terminal llama a esto al empezar, para el recorrido de la traza.
    func visitar(_ noTerminal: String) {
        recorrido.append("\(noTerminal)[\(actual.tipo == .fin ? "fin" : actual.texto)]")
    }

    /// Error en el token actual.
    func error(_ motivo: String) -> ErrorSintactico {
        ErrorSintactico(motivo, en: actual)
    }

    /// "'naves'" o "el final de la frase", para los mensajes de error.
    func describir(_ token: Token) -> String {
        token.tipo == .fin ? "el final de la frase" : "'\(token.texto)'"
    }

    // MARK: - Comprobaciones de FIRST

    /// El token actual puede empezar un `<sn>`: PRON, ART, POS, NUM o SUST.
    var empiezaSN: Bool {
        let c = claseActual
        if case .numero = actual.tipo { return true }
        return c.pronombre != nil || c.articulo != nil || c.posesivo != nil || !c.nominales.isEmpty
    }

    /// El token en `desplazamiento` es NUM o SUST (lo que puede seguir a un determinante).
    func esCantidadONombre(en desplazamiento: Int) -> Bool {
        if case .numero = token(en: desplazamiento).tipo { return true }
        return !clase(en: desplazamiento).nominales.isEmpty
    }
}

// MARK: - Resultados intermedios de cada no terminal

/// Un `<sn>` ya analizado, con lo que hace falta para la concordancia.
struct SNAnalizado {
    var sn: SN
    var token: Token
    var esPronombre: Bool
    /// Persona con la que concuerda el verbo (pv o p en pronombres; 3 en nombres).
    var persona: Int
    var plural: Bool
}

struct DeterminanteAnalizado {
    var token: Token
    /// Número que exige al nombre (rasgo n), o nil si no lo dice.
    var plural: Bool?
    var poseedor: Pronombre?
}

/// Un `<verbo>`: sus lecturas posibles (puede haber varias, R6).
struct VerboAnalizado {
    var lecturas: [RasgosVerbo]
    var perifrastico: Bool
    var token: Token
}

struct SVAnalizado {
    var verbo: VerboAnalizado
    var polaridad: Polaridad
}
