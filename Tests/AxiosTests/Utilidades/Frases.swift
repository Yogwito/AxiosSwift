import Foundation
@testable import AxiosCore

/// Tokens armados a mano sobre el contrato de Modelos.swift, como los entregaría el
/// analizador léxico de P1 (que todavía no está en el repo). Cada palabra va separada
/// por espacios, también los signos: "¿ Cuándo llegan ?". Un número en cifras es un
/// token `.numero`, ¿ y ? son `.interrogacion`, y se agrega `.fin` al final. La columna
/// es la posición real de cada pieza en la frase (desde 1).
func tokens(_ frase: String) -> [Token] {
    var resultado: [Token] = []
    var columna = 1
    for pieza in frase.split(separator: " ", omittingEmptySubsequences: false) {
        let texto = String(pieza)
        defer { columna += texto.count + 1 }
        guard !texto.isEmpty else { continue }
        let tipo: TipoToken
        if texto == "¿" || texto == "?" {
            tipo = .interrogacion
        } else if let n = Int(texto) {
            tipo = .numero(n)
        } else {
            tipo = .palabra
        }
        resultado.append(Token(tipo: tipo, texto: texto, linea: 1, columna: columna))
    }
    resultado.append(Token(tipo: .fin, texto: "", linea: 1, columna: columna))
    return resultado
}

/// BD en memoria con el léxico, las reglas y el vocabulario español reales.
let bdConVocabularioEspanol: BaseDatos = {
    let bd = try! BaseDatos(ruta: ":memory:")
    for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt", "vocab_es_v0.7.txt"] {
        _ = try! bd.cargar(archivo: archivoDatos(archivo))
    }
    return bd
}()
