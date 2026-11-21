// Analizador sintáctico del español (P2): de los tokens al árbol intermedio, según
// la BNF de docs/memoria.md.

import Foundation

public struct AnalizadorSintactico {
    /// Cantidad más grande que se acepta (regla R1). No es una regla del español ni
    /// de Kethari u Ozh: es el alcance que fija el enunciado ("cantidades hasta 9.999"),
    /// por eso es una constante y no un dato (bitácora 2026-11-21).
    public static let cantidadMaxima = 9_999

    let lexicon: Lexicon

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// Analiza una frase ya tokenizada (con o sin `.fin` al final) y devuelve su árbol,
    /// o el primer error con la columna del token donde ocurrió.
    public func analizar(_ tokens: [Token]) -> Result<Oracion, ErrorSintactico> {
        do {
            return .success(try Parser(tokens: tokens, lexicon: lexicon).entrada())
        } catch let error as ErrorSintactico {
            return .failure(error)
        } catch {
            // El parser solo lanza ErrorSintactico; esto no debería ocurrir.
            return .failure(ErrorSintactico(motivo: "\(error)", linea: 1, columna: 1))
        }
    }
}
