// Analizador léxico del español (P1): un AFD escrito a mano con su tabla de
// transiciones. Recibe el texto normalizado y da los tokens de Modelos.swift
// con la columna que tenían en la entrada original.

import Foundation

/// Error del analizador léxico, con la columna original.
public struct ErrorLexico: Error, Equatable {
    public var motivo: String
    public var linea: Int
    public var columna: Int

    public init(motivo: String, linea: Int, columna: Int) {
        self.motivo = motivo
        self.linea = linea
        self.columna = columna
    }

    /// "columna 5: carácter no válido '$'"
    public func texto() -> String {
        "columna \(columna): \(motivo)"
    }
}

public enum AnalizadorLexico {
    enum Clase: CaseIterable {
        case letra    // incluida la ñ
        case digito   // 0-9
        case signo    // ¿ ?
        case espacio
        case otro
    }

    enum Estado: CaseIterable {
        case inicio     // entre tokens
        case enPalabra
        case enNumero
        case enSigno    // un signo es un token de un carácter
        case error
    }

    /// δ(estado, clase). `error` es un sumidero y no tiene fila.
    static let transiciones: [Estado: [Clase: Estado]] = [
        .inicio:    [.letra: .enPalabra, .digito: .enNumero, .signo: .enSigno, .espacio: .inicio, .otro: .error],
        .enPalabra: [.letra: .enPalabra, .digito: .error,    .signo: .enSigno, .espacio: .inicio, .otro: .error],
        .enNumero:  [.letra: .error,     .digito: .enNumero, .signo: .enSigno, .espacio: .inicio, .otro: .error],
        .enSigno:   [.letra: .enPalabra, .digito: .enNumero, .signo: .enSigno, .espacio: .inicio, .otro: .error],
    ]

    static let aceptacion: Set<Estado> = [.inicio, .enPalabra, .enNumero, .enSigno]

    static func clase(_ c: Character) -> Clase {
        if c == "¿" || c == "?" { return .signo }
        if c.isASCII && c.isNumber { return .digito }
        if c.isLetter { return .letra }
        if c.isWhitespace { return .espacio }
        return .otro
    }

    /// Tokens de un texto sin normalizar (las columnas son las del propio texto).
    public static func analizar(_ texto: String) -> Result<[Token], ErrorLexico> {
        let n = texto.count
        return analizar(TextoNormalizado(texto: texto, columnas: (0..<n).map { $0 + 1 }, longitudOriginal: n))
    }

    /// Tokens del texto normalizado, terminados en `.fin`.
    public static func analizar(_ entrada: TextoNormalizado) -> Result<[Token], ErrorLexico> {
        var tokens: [Token] = []
        var estado = Estado.inicio
        var lexema = ""
        var inicio = 0  // columna original del lexema

        // Cierra el lexema en curso según el estado en que se leyó.
        func emitir() throws {
            switch estado {
            case .enPalabra:
                tokens.append(Token(tipo: .palabra, texto: lexema, linea: 1, columna: inicio))
            case .enNumero:
                guard let valor = Int(lexema) else {
                    throw ErrorLexico(motivo: "número demasiado grande '\(lexema)'", linea: 1, columna: inicio)
                }
                tokens.append(Token(tipo: .numero(valor), texto: lexema, linea: 1, columna: inicio))
            case .enSigno:
                tokens.append(Token(tipo: .interrogacion, texto: lexema, linea: 1, columna: inicio))
            case .inicio, .error:
                break
            }
            lexema = ""
        }

        do {
            for (i, c) in entrada.texto.enumerated() {
                let columna = entrada.columnaOriginal(i + 1)
                let cl = clase(c)
                guard let siguiente = transiciones[estado]?[cl], siguiente != .error else {
                    throw ErrorLexico(motivo: motivoError(estado, cl, c), linea: 1, columna: columna)
                }
                // Un token termina al cambiar de estado; cada signo es un token aparte.
                if siguiente != estado || estado == .enSigno {
                    try emitir()
                    inicio = columna
                }
                if siguiente != .inicio {
                    lexema.append(c)
                }
                estado = siguiente
            }
            guard aceptacion.contains(estado) else {
                throw ErrorLexico(motivo: "entrada incompleta", linea: 1, columna: entrada.columnaOriginal(entrada.columnas.count + 1))
            }
            try emitir()
        } catch let error as ErrorLexico {
            return .failure(error)
        } catch {
            return .failure(ErrorLexico(motivo: "\(error)", linea: 1, columna: 1))
        }

        let fin = entrada.columnaOriginal(entrada.columnas.count + 1)
        tokens.append(Token(tipo: .fin, texto: "", linea: 1, columna: fin))
        return .success(tokens)
    }

    private static func motivoError(_ estado: Estado, _ clase: Clase, _ c: Character) -> String {
        switch (estado, clase) {
        case (.enPalabra, .digito): return "cifra pegada a una palabra"
        case (.enNumero, .letra): return "letra pegada a un número"
        default: return "carácter no válido '\(c)'"
        }
    }

    /// Para la traza: "¿ SIGNO@1 · cuando PALABRA@2 · 15 NUM@16 · FIN@19".
    public static func texto(_ tokens: [Token]) -> String {
        tokens.map { t in
            switch t.tipo {
            case .palabra: return "\(t.texto) PALABRA@\(t.columna)"
            case .numero: return "\(t.texto) NUM@\(t.columna)"
            case .interrogacion: return "\(t.texto) SIGNO@\(t.columna)"
            case .fin: return "FIN@\(t.columna)"
            }
        }.joined(separator: " · ")
    }
}
