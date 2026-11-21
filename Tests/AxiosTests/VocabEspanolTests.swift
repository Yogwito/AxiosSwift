import XCTest
@testable import AxiosCore

final class VocabEspanolTests: XCTestCase {
    // MARK: - EntradaVocab

    func testEntradaVocabLeeLemasYRasgos() {
        let e = EntradaVocab(fila: "Fueron", lema: "ser, ir", categoria: "verbo", rasgos: "p=3;n=pl;t=pasado")
        XCTAssertEqual(e.forma, "fueron")
        XCTAssertEqual(e.lemas, ["ser", "ir"], "los candidatos conservan su orden")
        XCTAssertEqual(e.categoria, "verbo")
        XCTAssertEqual(e.rasgos, ["p": "3", "n": "pl", "t": "pasado"])
    }

    func testEntradaVocabQuitaTildesDeFormaYLemas() {
        let e = EntradaVocab(fila: "-án", lema: nil, categoria: "terminacion_futuro", rasgos: nil)
        XCTAssertEqual(e.forma, "-an")
        XCTAssertEqual(e.lemas, [])
        XCTAssertEqual(e.rasgos, [:])

        let su = EntradaVocab(fila: "su", lema: "él,ellos,usted,ustedes", categoria: "posesivo", rasgos: "n=sg")
        XCTAssertEqual(su.lemas, ["el", "ellos", "usted", "ustedes"])
    }

    func testEntradaVocabIgnoraRasgosMalFormados() {
        let e = EntradaVocab(fila: "x", lema: "x", categoria: nil, rasgos: "p=1;;sinvalor;=2; n = pl")
        XCTAssertEqual(e.rasgos, ["p": "1", "n": "pl"])
    }

    // MARK: - Contrato Lexicon

    /// Un Lexicon que no implementa `entradasEspanol` sigue compilando y devuelve [].
    private struct LexiconSinVocabulario: Lexicon {
        func traduccion(es: String, lengua: Lengua, en fecha: Date?) -> String? { nil }
        func regla(_ clave: String, lengua: Lengua) -> String? { nil }
        func vocabularioEspanol() -> Set<String> { [] }
        func categoria(forma: String, lengua: Lengua) -> String? { nil }
    }

    func testLexiconSinVocabularioDevuelveVacioPorDefecto() {
        XCTAssertEqual(LexiconSinVocabulario().entradasEspanol(forma: "van"), [])
    }

    func testLexiconFalsoBuscaSinTildes() {
        let lexicon = LexiconFalso(vocabEs: [
            EntradaVocab(fila: "-án", lema: "ar,er,ir", categoria: "terminacion_futuro", rasgos: "t=futuro"),
            EntradaVocab(fila: "-an", lema: "ar", categoria: "terminacion_presente", rasgos: "t=presente"),
            EntradaVocab(fila: "van", lema: "ir", categoria: "verbo", rasgos: "t=presente"),
        ])
        let categorias = lexicon.entradasEspanol(forma: "-AN").map(\.categoria)
        XCTAssertEqual(categorias, ["terminacion_futuro", "terminacion_presente"])
        XCTAssertEqual(lexicon.entradasEspanol(forma: "nada"), [])
    }
}
