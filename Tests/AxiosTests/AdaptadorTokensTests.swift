import XCTest
@testable import AxiosCore

final class AdaptadorTokensTests: XCTestCase {
    private func token(_ tipo: TipoToken, _ texto: String, _ columna: Int) -> Token {
        Token(tipo: tipo, texto: texto, linea: 1, columna: columna)
    }

    func testTokensDelContratoNoCambian() {
        let entrada = tokens("¿ Cuándo llegan 15 naves ?")
        XCTAssertEqual(AdaptadorTokens.adaptar(entrada), entrada)
    }

    func testQuitaLaPuntuacionYConservaLasPosiciones() {
        let entrada = [token(.palabra, "Queremos", 1), token(.palabra, "paz", 10), token(.palabra, ".", 13), token(.fin, "", 14)]
        XCTAssertEqual(AdaptadorTokens.adaptar(entrada), [entrada[0], entrada[1], entrada[3]])
    }

    func testSignosYCifrasQueLleganComoPalabra() {
        let adaptados = AdaptadorTokens.adaptar([
            token(.palabra, "¿", 1), token(.palabra, "15", 2), token(.palabra, "naves", 5), token(.palabra, "?", 10),
        ])
        XCTAssertEqual(adaptados.map(\.tipo), [.interrogacion, .numero(15), .palabra, .interrogacion, .fin])
        XCTAssertEqual(adaptados.map(\.columna), [1, 2, 5, 10, 11], "el fin va detrás del último token")
    }

    func testCortaEnElPrimerFin() {
        let adaptados = AdaptadorTokens.adaptar([token(.palabra, "llegan", 1), token(.fin, "", 7), token(.palabra, "sobra", 8)])
        XCTAssertEqual(adaptados.map(\.texto), ["llegan", ""])
    }

    func testEntradaVaciaDaSoloFin() {
        XCTAssertEqual(AdaptadorTokens.adaptar([]).map(\.tipo), [.fin])
    }

    func testUnaFraseConPuntoSeAnalizaTrasAdaptar() {
        let conPunto = [token(.palabra, "Queremos", 1), token(.palabra, "paz", 10), token(.palabra, ".", 13)]
        let analizador = AnalizadorSintactico(lexicon: bdConVocabularioEspanol)
        guard case .failure = analizador.analizar(conPunto) else {
            return XCTFail("sin adaptar, el punto es una palabra desconocida")
        }
        guard case .success(let oracion) = analizador.analizar(AdaptadorTokens.adaptar(conPunto)) else {
            return XCTFail("adaptada debería analizarse")
        }
        XCTAssertEqual(oracion.texto(), "declarativa · S: omitido · V: querer 1pl presente · O: paz")
    }
}
