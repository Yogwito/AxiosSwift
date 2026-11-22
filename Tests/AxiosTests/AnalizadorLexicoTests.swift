import XCTest
@testable import AxiosCore

final class AnalizadorLexicoTests: XCTestCase {
    private func tokens(_ texto: String) -> [Token] {
        guard case .success(let t) = AnalizadorLexico.analizar(texto) else {
            XCTFail("'\(texto)' debía ser válido")
            return []
        }
        return t
    }

    private func error(_ texto: String) -> ErrorLexico? {
        guard case .failure(let e) = AnalizadorLexico.analizar(texto) else { return nil }
        return e
    }

    func testPreguntaSencilla() {
        let t = tokens("¿cuando llegan?")
        XCTAssertEqual(t.map(\.tipo), [.interrogacion, .palabra, .palabra, .interrogacion, .fin])
        XCTAssertEqual(t.map(\.texto), ["¿", "cuando", "llegan", "?", ""])
        XCTAssertEqual(t.map(\.columna), [1, 2, 9, 15, 16])
        XCTAssertTrue(t.allSatisfy { $0.linea == 1 })
    }

    func testNumero() {
        let t = tokens("llegaron 15 naves")
        XCTAssertEqual(t.map(\.tipo), [.palabra, .numero(15), .palabra, .fin])
        XCTAssertEqual(t[1].columna, 10)
    }

    func testSignosPegados() {
        XCTAssertEqual(tokens("¿15?").map(\.tipo), [.interrogacion, .numero(15), .interrogacion, .fin])
        XCTAssertEqual(tokens("??").map(\.tipo), [.interrogacion, .interrogacion, .fin], "cada signo es un token")
    }

    func testEnieEsLetra() {
        XCTAssertEqual(tokens("año").map(\.tipo), [.palabra, .fin])
    }

    func testEntradaVaciaSoloTieneFin() {
        let t = tokens("")
        XCTAssertEqual(t.map(\.tipo), [.fin])
        XCTAssertEqual(t[0].columna, 1)
    }

    func testColumnasDeLaEntradaOriginal() {
        let normalizado = Normalizador().normalizar("¿CUÁNDO   llegan?")
        guard case .success(let t) = AnalizadorLexico.analizar(normalizado) else { return XCTFail() }
        XCTAssertEqual(t.map(\.texto), ["¿", "cuando", "llegan", "?", ""])
        XCTAssertEqual(t.map(\.columna), [1, 2, 11, 17, 18])
    }

    func testNumeroEnLetrasTieneLaColumnaDeSuPrimeraPalabra() {
        let numerales = [("dos", "v=2;tipo=unidad"), ("mil", "v=1000;tipo=mil"), ("quince", "v=15;tipo=unidad")]
            .map { EntradaVocab(fila: $0.0, lema: nil, categoria: "numeral", rasgos: $0.1) }
        let normalizado = Normalizador(lexicon: LexiconFalso(vocabEs: numerales))
            .normalizar("¿Llegaron dos mil quince naves?")
        guard case .success(let t) = AnalizadorLexico.analizar(normalizado) else { return XCTFail() }
        XCTAssertEqual(t.map(\.tipo), [.interrogacion, .palabra, .numero(2015), .palabra, .interrogacion, .fin])
        XCTAssertEqual(t.map(\.columna), [1, 2, 11, 26, 31, 32])
    }

    func testCaracterNoValidoConSuColumna() {
        XCTAssertEqual(error("nave$"), ErrorLexico(motivo: "carácter no válido '$'", linea: 1, columna: 5))

        let normalizado = Normalizador().normalizar("¿Llegan   naves$?")
        guard case .failure(let e) = AnalizadorLexico.analizar(normalizado) else { return XCTFail() }
        XCTAssertEqual(e.columna, 16, "columna en lo que escribió el usuario")
    }

    func testCifraPegadaAUnaPalabra() {
        XCTAssertEqual(error("nave1"), ErrorLexico(motivo: "cifra pegada a una palabra", linea: 1, columna: 5))
    }

    func testLetraPegadaAUnNumero() {
        XCTAssertEqual(error("15naves"), ErrorLexico(motivo: "letra pegada a un número", linea: 1, columna: 3))
    }

    func testNumeroDemasiadoGrande() {
        XCTAssertEqual(error("llegan 99999999999999999999999")?.columna, 8)
    }

    func testTextoDelError() {
        XCTAssertEqual(error("nave$")?.texto(), "columna 5: carácter no válido '$'")
    }

    func testLaTablaTieneUnaTransicionPorEstadoYClase() {
        for estado in AnalizadorLexico.Estado.allCases where estado != .error {
            for clase in AnalizadorLexico.Clase.allCases {
                XCTAssertNotNil(AnalizadorLexico.transiciones[estado]?[clase], "falta δ(\(estado), \(clase))")
            }
        }
        XCTAssertFalse(AnalizadorLexico.aceptacion.contains(.error))
    }

    func testTrazaDeLosTokens() {
        XCTAssertEqual(
            AnalizadorLexico.texto(tokens("¿cuando llegan 15?")),
            "¿ SIGNO@1 · cuando PALABRA@2 · llegan PALABRA@9 · 15 NUM@16 · ? SIGNO@18 · FIN@19"
        )
    }

    func testElSintacticoEntiendeLosTokens() {
        let analizador = AnalizadorSintactico(lexicon: bdConVocabularioEspanol)
        guard case .success = analizador.analizar(tokens("¿cuando llegan?")) else {
            return XCTFail("los tokens deben cumplir el contrato de Modelos.swift")
        }
    }
}
