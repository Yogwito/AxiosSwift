import XCTest
@testable import AxiosCore

final class MorfologiaTests: XCTestCase {
    /// BD en memoria con el léxico y el vocabulario español reales.
    private static let bd: BaseDatos = {
        let bd = try! BaseDatos(ruta: ":memory:")
        _ = try! bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        _ = try! bd.cargar(archivo: archivoDatos("vocab_es_v0.7.txt"))
        return bd
    }()

    private let morfologia = Morfologia(lexicon: MorfologiaTests.bd)

    private func rasgos(_ raiz: String, _ persona: Int, _ plural: Bool, _ tiempo: Tiempo) -> RasgosVerbo {
        RasgosVerbo(raiz: raiz, persona: persona, plural: plural, tiempo: tiempo)
    }

    /// Solo los rasgos de cada lectura, en orden.
    private func lecturas(_ forma: String) -> [RasgosVerbo] {
        morfologia.analizarVerbo(forma).map(\.rasgos)
    }

    // MARK: - Verbos regulares

    func testEnviaronEsPasadoTerceraPlural() {
        let analisis = morfologia.analizarVerbo("enviaron")
        XCTAssertEqual(analisis.map(\.rasgos), [rasgos("enviar", 3, true, .pasado)])
        XCTAssertEqual(analisis.first?.procedencia, .regular)
        XCTAssertEqual(analisis.first?.terminacion, "-aron")
        XCTAssertEqual(analisis.first?.texto(), "enviar 3pl pasado")
    }

    func testQueremosEsPresentePrimeraPlural() {
        XCTAssertEqual(lecturas("queremos"), [rasgos("querer", 1, true, .presente)])
    }

    func testLleganEsPresenteTerceraPlural() {
        XCTAssertEqual(lecturas("llegan"), [rasgos("llegar", 3, true, .presente)])
    }

    // "-an" es presente y futuro ("-án"): en "llegarán" solo el futuro deja un verbo conocido.
    func testFuturoVaPegadoAlInfinitivo() {
        XCTAssertEqual(lecturas("llegarán"), [rasgos("llegar", 3, true, .futuro)])
        XCTAssertEqual(lecturas("llegaran"), [rasgos("llegar", 3, true, .futuro)], "sin tilde da lo mismo")
        XCTAssertEqual(lecturas("esperaremos"), [rasgos("esperar", 1, true, .futuro)])
    }

    // "enviamos" es igual en presente y en pasado: se devuelven las dos lecturas.
    func testEnviamosEsAmbiguaYDevuelveLosDosCandidatos() {
        XCTAssertEqual(lecturas("enviamos"), [
            rasgos("enviar", 1, true, .presente),
            rasgos("enviar", 1, true, .pasado),
        ])
        XCTAssertEqual(lecturas("llegamos").count, 2)
    }

    // Sin tilde "llegó" se escribe como "llego": presente 1.ª singular o pasado 3.ª singular.
    func testSinTildeLlegoEsAmbigua() {
        XCTAssertEqual(lecturas("llego"), [
            rasgos("llegar", 1, false, .presente),
            rasgos("llegar", 3, false, .pasado),
        ])
    }

    func testMayusculasYTildesNoImportan() {
        XCTAssertEqual(lecturas("ENVIARON"), lecturas("enviaron"))
    }

    // MARK: - Lo que no es un verbo conjugado

    func testPalabraDesconocidaNoTieneLecturas() {
        XCTAssertEqual(lecturas("caminaron"), [], "caminar no está en el léxico")
        XCTAssertEqual(lecturas("naves"), [])
        XCTAssertEqual(lecturas("a"), [])
        XCTAssertEqual(lecturas(""), [])
    }

    func testElInfinitivoNoEsUnaFormaConjugada() {
        XCTAssertEqual(lecturas("llegar"), [])
    }

    // MARK: - El algoritmo no conoce ningún verbo

    /// Con un léxico inventado, el mismo código analiza un verbo que no existe en español:
    /// las terminaciones y los verbos están en los datos, no en el código.
    func testFuncionaConUnVerboInventado() {
        let lexicon = LexiconFalso(
            categorias: [.es: ["blorar": "verbo"]],
            vocabEs: [
                EntradaVocab(fila: "-aron", lema: "ar", categoria: "terminacion_pasado", rasgos: "p=3;n=pl;t=pasado;base=raiz"),
            ]
        )
        let analisis = Morfologia(lexicon: lexicon).analizarVerbo("bloraron")
        XCTAssertEqual(analisis.map(\.rasgos), [rasgos("blorar", 3, true, .pasado)])
        XCTAssertEqual(Morfologia(lexicon: lexicon).analizarVerbo("enviaron"), [], "enviar no está en este léxico")
    }
}
