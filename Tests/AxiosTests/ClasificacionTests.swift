import XCTest
@testable import AxiosCore

/// Terminales de la BNF: a qué categorías pertenece cada token según los datos.
final class ClasificacionTests: XCTestCase {
    private static let bd: BaseDatos = {
        let bd = try! BaseDatos(ruta: ":memory:")
        _ = try! bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        _ = try! bd.cargar(archivo: archivoDatos("vocab_es_v0.7.txt"))
        return bd
    }()

    private let clasificador = Clasificador(lexicon: ClasificacionTests.bd)

    private func clase(_ texto: String) -> ClaseToken {
        clasificador.clasificar(Token(tipo: .palabra, texto: texto, linea: 1, columna: 1))
    }

    func testElEsArticuloYPronombreSinTildes() {
        let el = clase("el")
        XCTAssertNotNil(el.articulo)
        XCTAssertEqual(el.pronombre?.lemaPreferido, "el")
        XCTAssertEqual(el.pronombre?.persona, 3)
    }

    func testUstedesConcuerdaEnTercera() {
        let ustedes = clase("Ustedes").pronombre
        XCTAssertEqual(ustedes?.persona, 2)
        XCTAssertEqual(ustedes?.personaConcordancia, 3)
        XCTAssertEqual(ustedes?.plural, true)
    }

    func testInterrogativosConSuFuncion() {
        XCTAssertEqual(clase("cuándo").interrogativo?.rasgos["f"], "circunstancial")
        XCTAssertEqual(clase("quien").interrogativo?.rasgos["f"], "sujeto")
        XCTAssertEqual(clase("Cuántas").interrogativo?.lemaPreferido, "cuantos")
        XCTAssertEqual(clase("que").interrogativo?.rasgos["f"], "objeto")
    }

    func testPalabrasGramaticales() {
        XCTAssertTrue(clase("no").negacion)
        XCTAssertEqual(clase("a").preposicion, "a")
        XCTAssertEqual(clase("nuestro").posesivo?.lemaPreferido, "nosotros")
    }

    func testCategoriasDeLaMorfologia() {
        XCTAssertEqual(clase("naves").nominales, [AnalisisNominal(lema: "nave", plural: true)])
        XCTAssertEqual(clase("vendrán").verbos.first?.rasgos.raiz, "venir")
        XCTAssertEqual(clase("llegar").infinitivo, "llegar")
    }

    func testPalabraDesconocidaNoTieneCategorias() {
        XCTAssertFalse(clase("xyz").esConocida)
        XCTAssertTrue(clase("cuando").esConocida)
    }

    func testLosTokensQueNoSonPalabrasNoSeClasificanPorDatos() {
        let numero = clasificador.clasificar(Token(tipo: .numero(15), texto: "15", linea: 1, columna: 1))
        XCTAssertFalse(numero.esConocida)
    }

    func testPerifrasisYPoseedores() {
        let ir = clasificador.perifrasis(de: "ir")
        XCTAssertEqual(ir.first?.lemas, ["a"])
        XCTAssertEqual(ir.first?.rasgos["resultado"], "futuro")
        XCTAssertEqual(clasificador.pronombre(lema: "nosotros"), Pronombre(lema: "nosotros", persona: 1, plural: true))
        XCTAssertNil(clasificador.pronombre(lema: "nave"))
    }

    func testErrorSintacticoGuardaLaPosicion() {
        let token = Token(tipo: .palabra, texto: "xyz", linea: 1, columna: 9)
        let error = ErrorSintactico("palabra desconocida 'xyz'", en: token)
        XCTAssertEqual(error, ErrorSintactico(motivo: "palabra desconocida 'xyz'", linea: 1, columna: 9))
        XCTAssertEqual(error.texto(), "columna 9: palabra desconocida 'xyz'")
    }
}
