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

    // MARK: - Fases en la traza

    private func traza(_ entrada: [Token]) -> (Result<Oracion, ErrorSintactico>, Traza) {
        var traza = Traza()
        let resultado = analizador.analizar(entrada, traza: &traza)
        return (resultado, traza)
    }

    func testTrazaDeCuandoLlegan() throws {
        let (resultado, t) = traza(tokens("¿ Cuándo llegan ?"))
        XCTAssertEqual(try resultado.get(), try arbol("¿ Cuándo llegan ?"))
        XCTAssertEqual(t.texto(), """
            [morfologia] Cuándo: — | llegan: llegar 3pl presente
            [clasificacion] ¿ SIGNO · Cuándo INTERROG · llegan VERBO · ? SIGNO · FIN
            [sintaxis] entrada[¿] › clausula[Cuándo] › sintInterrog[Cuándo] › nucleo[llegan] › sv[llegan] › verbo[llegan]
            [arbol] parcial(cuando, circunstancial) · S: omitido · V: llegar 3pl presente · O: —
            """)
    }

    func testLasFasesVanDetrasDeLasAnteriores() {
        var t = Traza()
        t.agregar(fase: "lexico", salida: "4 tokens")
        _ = analizador.analizar(tokens("Queremos paz"), traza: &t)
        XCTAssertEqual(t.fases.map(\.nombre), ["lexico", "morfologia", "clasificacion", "sintaxis", "arbol"])
    }

    func testClasificacionMuestraLasCategoriasAmbiguas() {
        let (_, t) = traza(tokens("¿ Es el una criatura ?"))
        XCTAssertEqual(
            t.fases.first { $0.nombre == "clasificacion" }?.salida,
            "¿ SIGNO · Es VERBO · el PRON/ART · una ART · criatura SUST · ? SIGNO · FIN"
        )
    }

    func testTrazaDeUnErrorLlevaLaColumna() {
        let (resultado, t) = traza(tokens("¿ Cuándo xyz ?"))
        XCTAssertEqual(resultado, .failure(ErrorSintactico(motivo: "palabra desconocida 'xyz'", linea: 1, columna: 10)))
        XCTAssertEqual(t.fases.map(\.nombre), ["morfologia", "clasificacion", "sintaxis", "arbol"])
        XCTAssertEqual(t.fases[1].salida, "¿ SIGNO · Cuándo INTERROG · xyz desconocida · ? SIGNO · FIN")
        XCTAssertEqual(t.fases[3].salida, "error · columna 10: palabra desconocida 'xyz'")
    }

    func testElEngancheAdaptaLosTokens() throws {
        // El punto final llega como palabra: el enganche lo quita antes de analizar.
        var conPunto = tokens("Queremos paz")
        conPunto.insert(Token(tipo: .palabra, texto: ".", linea: 1, columna: 13), at: 2)
        let (resultado, _) = traza(conPunto)
        XCTAssertEqual(try resultado.get().texto(), "declarativa · S: omitido · V: querer 1pl presente · O: paz")
    }

    func testFasesConNumeroYPerifrasis() {
        let (_, t) = traza(tokens("No van a llegar 15 naves"))
        XCTAssertEqual(
            t.fases.first { $0.nombre == "morfologia" }?.salida,
            "No: — | van: ir 3pl presente | a: — | llegar: inf llegar | naves: nave+pl"
        )
        XCTAssertEqual(
            t.fases.last?.salida,
            "declarativa · S: 15 nave+pl · V: llegar 3pl futuro (ir a) negativa · O: —"
        )
    }

    func testRecorridoSeQuedaDondeFalla() {
        let parser = Parser(tokens: tokens("Nosotros no los vimos"), lexicon: bdConVocabularioEspanol)
        XCTAssertThrowsError(try parser.entrada())
        XCTAssertEqual(parser.recorrido.last, "verbo[los]")
    }
}
