import Foundation

/// Error del tokenizador: qué pasó y en qué columna (desde 1).
public struct ErrorLexicoAlien: Error, Equatable {
    public var motivo: String
    public var columna: Int

    public init(motivo: String, columna: Int) {
        self.motivo = motivo
        self.columna = columna
    }
}

/// Tokenizador de frases en Kethari u Ozh: un AFD escrito a mano con su tabla de
/// transiciones explícita. No conoce ninguna palabra; solo separa palabras y
/// comprueba que el guion aparezca únicamente entre letras ("a-b").
public enum TokenizadorAlien {
    /// Clases de caracteres del alfabeto de entrada.
    enum Clase: CaseIterable {
        case letra    // cualquier letra, incluidas ʔ y ü
        case guion    // "-"
        case espacio  // espacios y tabuladores
        case otro     // cualquier otro carácter
    }

    enum Estado {
        case inicio     // entre palabras
        case enPalabra  // leyendo letras de una palabra
        case trasGuion  // acaba de leer un guion: solo puede seguir una letra
        case error
    }

    /// δ(estado, clase). `error` es un estado sumidero y no tiene fila.
    static let transiciones: [Estado: [Clase: Estado]] = [
        .inicio: [.letra: .enPalabra, .guion: .error, .espacio: .inicio, .otro: .error],
        .enPalabra: [.letra: .enPalabra, .guion: .trasGuion, .espacio: .inicio, .otro: .error],
        .trasGuion: [.letra: .enPalabra, .guion: .error, .espacio: .error, .otro: .error],
    ]

    /// Estados en los que puede terminar la entrada.
    static let aceptacion: Set<Estado> = [.inicio, .enPalabra]

    static func clase(_ c: Character) -> Clase {
        if c == "-" { return .guion }
        if c.isWhitespace { return .espacio }
        if c == "ʔ" || c == "ü" || c.isLetter { return .letra }
        return .otro
    }

    /// Divide `s` en palabras con su columna (desde 1) y agrega un token `.fin`.
    public static func tokenizar(_ s: String) -> Result<[Token], ErrorLexicoAlien> {
        var tokens: [Token] = []
        var estado = Estado.inicio
        var palabra = ""
        var inicioPalabra = 0
        var columnaGuion = 0
        var columna = 0

        for c in s {
            columna += 1
            let cl = clase(c)
            guard let siguiente = transiciones[estado]?[cl] else { break }

            if siguiente == .error {
                return .failure(ErrorLexicoAlien(
                    motivo: motivoError(desde: estado, clase: cl, caracter: c),
                    columna: (cl == .espacio && estado == .trasGuion) ? columnaGuion : columna
                ))
            }
            switch (estado, siguiente) {
            case (.inicio, .enPalabra):
                palabra = String(c)
                inicioPalabra = columna
            case (.enPalabra, .inicio):
                tokens.append(Token(tipo: .palabra, texto: palabra, linea: 1, columna: inicioPalabra))
                palabra = ""
            case (_, .trasGuion):
                palabra.append(c)
                columnaGuion = columna
            case (_, .enPalabra):
                palabra.append(c)
            default:
                break
            }
            estado = siguiente
        }

        guard aceptacion.contains(estado) else {
            return .failure(ErrorLexicoAlien(motivo: "guion al final de una palabra", columna: columnaGuion))
        }
        if estado == .enPalabra {
            tokens.append(Token(tipo: .palabra, texto: palabra, linea: 1, columna: inicioPalabra))
        }
        tokens.append(Token(tipo: .fin, texto: "", linea: 1, columna: columna + 1))
        return .success(tokens)
    }

    private static func motivoError(desde estado: Estado, clase: Clase, caracter: Character) -> String {
        switch (estado, clase) {
        case (_, .otro): return "carácter no válido '\(caracter)'"
        case (.inicio, .guion): return "guion al inicio de una palabra"
        case (.trasGuion, .guion): return "dos guiones seguidos"
        case (.trasGuion, .espacio): return "guion al final de una palabra"
        default: return "carácter inesperado '\(caracter)'"
        }
    }
}
