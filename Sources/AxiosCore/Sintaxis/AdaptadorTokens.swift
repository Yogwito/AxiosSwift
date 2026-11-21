// Capa de adaptación entre el analizador léxico (P1) y el sintáctico (P2). El código de
// P1 todavía no está en el repo: el analizador sintáctico se hizo sobre el contrato de
// Modelos.swift (Token/TipoToken), y esta capa absorbe las diferencias de forma más
// probables sin tocar ese contrato. Si P1 entrega exactamente el contrato, no cambia nada.

import Foundation

public enum AdaptadorTokens {
    /// Deja los tokens como los espera la BNF:
    /// - corta en el primer `.fin` (lo que venga después se ignora) y agrega `.fin` si falta;
    /// - quita los `.palabra` sin letras ni cifras (".", ",", "!", "¡"): la gramática no
    ///   tiene más signos que los de pregunta;
    /// - convierte en `.interrogacion` un "¿" o "?" que llegue como `.palabra`;
    /// - convierte en `.numero` una `.palabra` hecha solo de cifras ("15").
    /// No cambia ni el texto ni la posición de ningún token.
    public static func adaptar(_ entrada: [Token]) -> [Token] {
        var salida: [Token] = []
        for token in entrada {
            if token.tipo == .fin {
                salida.append(token)
                return salida
            }
            guard token.tipo == .palabra else {
                salida.append(token)
                continue
            }
            if token.texto == "¿" || token.texto == "?" {
                salida.append(Token(tipo: .interrogacion, texto: token.texto, linea: token.linea, columna: token.columna))
            } else if !token.texto.isEmpty, token.texto.allSatisfy(\.isASCIIDigit), let n = Int(token.texto) {
                salida.append(Token(tipo: .numero(n), texto: token.texto, linea: token.linea, columna: token.columna))
            } else if token.texto.contains(where: { $0.isLetter || $0.isNumber }) {
                salida.append(token)
            }
            // Si no tiene letras ni cifras es puntuación: se descarta.
        }
        let ultimo = salida.last ?? entrada.last
        let columna = ultimo.map { $0.columna + $0.texto.count } ?? 1
        salida.append(Token(tipo: .fin, texto: "", linea: ultimo?.linea ?? 1, columna: columna))
        return salida
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
