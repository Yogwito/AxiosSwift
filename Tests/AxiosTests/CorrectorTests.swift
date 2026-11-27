import XCTest
@testable import AxiosCore

final class CorrectorTests: XCTestCase {
    private func lexicos(_ texto: String) -> [Token] {
        guard case .success(let t) = AnalizadorLexico.analizar(texto) else {
            XCTFail("'\(texto)' debía ser válido")
            return []
        }
        return t
    }

    /// Texto de cada palabra después de corregir, con los datos reales.
    private func corregido(_ texto: String) -> [String] {
        Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos(texto)).tokens
            .filter { $0.tipo == .palabra }.map(\.texto)
    }

    func testDistancia() {
        XCTAssertEqual(Corrector.distancia("", "abc"), 3)
        XCTAssertEqual(Corrector.distancia("abc", ""), 3)
        XCTAssertEqual(Corrector.distancia("paz", "paz"), 0)
        XCTAssertEqual(Corrector.distancia("gato", "pato"), 1, "sustitución")
        XCTAssertEqual(Corrector.distancia("nave", "naves"), 1, "inserción")
        XCTAssertEqual(Corrector.distancia("kitten", "sitting"), 3)
        XCTAssertEqual(Corrector.distancia("lelgan", "llegan"), 2, "dos letras cambiadas de lugar")
        XCTAssertEqual(Corrector.distancia("año", "ano"), 1, "la ñ es otra letra")
    }

    func testPalabrasValidasNoCambian() {
        let r = Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos("¿cuando llegan las naves?"))
        XCTAssertTrue(r.correcciones.isEmpty)
        XCTAssertEqual(r.tokens, lexicos("¿cuando llegan las naves?"))
    }

    func testFormasQueReconoceLaMorfologiaNoCambian() {
        XCTAssertEqual(corregido("vendran fue queremos paz enviaron"), ["vendran", "fue", "queremos", "paz", "enviaron"])
    }

    func testNumerosYSignosNoSeTocan() {
        let r = Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos("¿15?"))
        XCTAssertEqual(r.tokens.map(\.tipo), [.interrogacion, .numero(15), .interrogacion, .fin])
        XCTAssertTrue(r.correcciones.isEmpty)
    }

    func testCorrigeUnaPalabraDelVocabulario() {
        XCTAssertEqual(corregido("kuando"), ["cuando"])
    }

    func testCorrigeUnVerboConjugado() {
        XCTAssertEqual(corregido("lelgaron"), ["llegaron"], "'llegaron' no está en el vocabulario: sale de la morfología")
    }

    func testCorrigeUnPlural() {
        XCTAssertEqual(corregido("nabes"), ["naves"])
    }

    func testConservaLaColumnaYDevuelveLasCorrecciones() {
        let r = Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos("¿kuando lelgaron?"))
        XCTAssertEqual(r.tokens.map(\.texto), ["¿", "cuando", "llegaron", "?", ""])
        XCTAssertEqual(r.tokens.map(\.columna), [1, 2, 9, 17, 18])
        XCTAssertEqual(r.correcciones, [
            Correccion(original: "kuando", corregida: "cuando", distancia: 1),
            Correccion(original: "lelgaron", corregida: "llegaron", distancia: 2),
        ])
    }

    func testLaFraseCorregidaLaEntiendeElSintactico() {
        let r = Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos("¿kuando lelgaron?"))
        guard case .success = AnalizadorSintactico(lexicon: bdConVocabularioEspanol).analizar(r.tokens) else {
            return XCTFail("tras corregir, la frase debe ser válida")
        }
    }

    func testNoCambiaUnaPalabraDesconocidaPorOtraQueNoSignificaLoMismo() {
        // "tener" no está en los datos; antes salía "tienen → venen" (distancia 2 en 6 letras).
        let r = Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos("¿tienen telescopio?"))
        XCTAssertEqual(r.tokens.map(\.texto), ["¿", "tienen", "telescopio", "?", ""])
        XCTAssertTrue(r.correcciones.isEmpty)
    }

    func testPalabraMuyDistintaNoSeCorrige() {
        let r = Corrector(lexicon: bdConVocabularioEspanol).corregir(lexicos("xyzqw"))
        XCTAssertEqual(r.tokens.first?.texto, "xyzqw", "la rechazará el sintáctico como desconocida")
        XCTAssertTrue(r.correcciones.isEmpty)
    }

    func testUmbralSegunLaLongitud() {
        let corrector = Corrector(lexicon: LexiconFalso(vocabulario: ["mensaje", "paz", "llegan"]))
        XCTAssertEqual(corrector.correccion(de: "mensjae")?.corregida, "mensaje", "7 letras: hasta 2 cambios")
        XCTAssertNil(corrector.correccion(de: "mnsjae"), "3 cambios es demasiado")
        XCTAssertNil(corrector.correccion(de: "lelgan"), "6 letras: solo 1 cambio")
        XCTAssertEqual(corrector.correccion(de: "pax")?.corregida, "paz", "3 letras: hasta 1 cambio")
        XCTAssertNil(corrector.correccion(de: "pz"), "2 letras o menos no se corrigen")
    }

    func testEmpateNoSeCorrige() {
        let corrector = Corrector(lexicon: LexiconFalso(vocabulario: ["paz", "vas"]))
        XCTAssertNil(corrector.correccion(de: "pas"), "paz y vas están a 1: no se adivina")
    }

    func testTextoParaLaTraza() {
        XCTAssertEqual(Corrector.texto([]), "sin cambios")
        XCTAssertEqual(
            Corrector.texto([
                Correccion(original: "kuando", corregida: "cuando", distancia: 1),
                Correccion(original: "lelgan", corregida: "llegan", distancia: 2),
            ]),
            "kuando → cuando (1) · lelgan → llegan (2)"
        )
    }
}
