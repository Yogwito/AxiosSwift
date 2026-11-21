import XCTest
@testable import AxiosCore

/// Salida de las fases de P2 para el modo traza.
final class TrazaSintaxisTests: CasoSintaxis {
    // MARK: - Recorrido de no terminales

    func testRecorridoSigueLaBNF() throws {
        let parser = Parser(tokens: tokens("¿ Cuándo llegan ?"), lexicon: bdConVocabularioEspanol)
        _ = try parser.entrada()
        XCTAssertEqual(parser.recorrido, [
            "entrada[¿]", "clausula[Cuándo]", "sintInterrog[Cuándo]", "nucleo[llegan]", "sv[llegan]", "verbo[llegan]",
        ])
    }

    func testRecorridoDeUnaFraseConSintagmas() throws {
        let parser = Parser(tokens: tokens("Ellos visitaron nuestro mundo"), lexicon: bdConVocabularioEspanol)
        _ = try parser.entrada()
        XCTAssertEqual(parser.recorrido, [
            "entrada[Ellos]", "clausula[Ellos]", "nucleo[Ellos]", "sn[Ellos]", "sv[visitaron]", "verbo[visitaron]",
            "sn[nuestro]", "determinante[nuestro]", "nominal[mundo]",
        ])
    }

    func testRecorridoSeQuedaDondeFalla() {
        let parser = Parser(tokens: tokens("Nosotros no los vimos"), lexicon: bdConVocabularioEspanol)
        XCTAssertThrowsError(try parser.entrada())
        XCTAssertEqual(parser.recorrido.last, "verbo[los]")
    }
}
