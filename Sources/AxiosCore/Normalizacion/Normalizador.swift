// Normalizador (P1): minúsculas, sin tildes (salvo la ñ), solo ¿ ? como signos,
// un espacio entre palabras y números en letras a cifras. Guarda la columna
// original de cada carácter.

import Foundation

/// Texto normalizado y la columna original (desde 1) de cada carácter.
public struct TextoNormalizado: Equatable {
    public var texto: String
    public var columnas: [Int]
    public var longitudOriginal: Int

    public init(texto: String, columnas: [Int], longitudOriginal: Int) {
        self.texto = texto
        self.columnas = columnas
        self.longitudOriginal = longitudOriginal
    }

    /// Columna original de una columna del texto normalizado.
    /// Fuera del texto devuelve la que sigue al final del original.
    public func columnaOriginal(_ columna: Int) -> Int {
        guard columna >= 1, columna <= columnas.count else { return longitudOriginal + 1 }
        return columnas[columna - 1]
    }
}

public struct Normalizador {
    /// Con léxico también convierte los números en letras ("quince" → "15").
    let lexicon: Lexicon?

    public init(lexicon: Lexicon? = nil) {
        self.lexicon = lexicon
    }

    public func normalizar(_ entrada: String) -> TextoNormalizado {
        let limpio = limpiar(entrada)
        guard let lexicon else { return limpio }
        return NumerosEnLetras(lexicon: lexicon).convertir(limpio)
    }

    /// Minúsculas, tildes, signos y espacios.
    func limpiar(_ entrada: String) -> TextoNormalizado {
        let original = Array(entrada)
        var salida: [Character] = []
        var columnas: [Int] = []
        var separadorPendiente: Int?  // columna del espacio que falta escribir

        func escribir(_ c: Character, columna: Int) {
            if let separador = separadorPendiente, !salida.isEmpty {
                salida.append(" ")
                columnas.append(separador)
            }
            separadorPendiente = nil
            salida.append(c)
            columnas.append(columna)
        }

        func separar(columna: Int) {
            if separadorPendiente == nil {
                separadorPendiente = columna
            }
        }

        for (i, c) in original.enumerated() {
            let columna = i + 1
            if c.isWhitespace {
                separar(columna: columna)
            } else if Normalizador.esSignoDePregunta(c) {
                // "??" cuenta como uno
                if salida.last == c && separadorPendiente == nil { continue }
                escribir(c, columna: columna)
            } else if Normalizador.esTildeSuelta(c) {
                continue  // "cu´ando" → "cuando"
            } else if c.isPunctuation {
                // Entre cifras es separador de miles: "9.999" → "9999"
                let entreCifras = i > 0 && i + 1 < original.count
                    && original[i - 1].isNumber && original[i + 1].isNumber
                if !entreCifras {
                    separar(columna: columna)
                }
            } else {
                // Los símbolos como "$" se dejan: los rechaza el analizador léxico
                for plegado in Normalizador.plegar(c) {
                    escribir(plegado, columna: columna)
                }
            }
        }

        return TextoNormalizado(texto: String(salida), columnas: columnas, longitudOriginal: original.count)
    }

    static func esSignoDePregunta(_ c: Character) -> Bool {
        c == "¿" || c == "?"
    }

    /// Acento sin letra: ´ ` ¨ ^
    static func esTildeSuelta(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && c.unicodeScalars.first?.properties.generalCategory == .modifierSymbol
    }

    /// Minúscula y sin tildes; la ñ se conserva.
    static func plegar(_ c: Character) -> String {
        let minuscula = c.lowercased()
        if minuscula == "ñ" { return minuscula }
        return minuscula.folding(options: .diacriticInsensitive, locale: nil)
    }
}
