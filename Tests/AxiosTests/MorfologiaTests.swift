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

    // MARK: - Irregulares

    // venir: raíz irregular "vendr-" en el futuro.
    func testVendranEsFuturoDeVenirPorRaizIrregular() {
        let analisis = morfologia.analizarVerbo("vendrán")
        XCTAssertEqual(analisis.map(\.rasgos), [rasgos("venir", 3, true, .futuro)])
        XCTAssertEqual(analisis.first?.procedencia, .raizIrregular)
        XCTAssertEqual(analisis.first?.terminacion, "-an")
    }

    // venir: raíz "vien-" en el presente, pero "venimos" es regular.
    func testVienenYVenimos() {
        XCTAssertEqual(lecturas("vienen"), [rasgos("venir", 3, true, .presente)])
        XCTAssertEqual(lecturas("viene"), [rasgos("venir", 3, false, .presente)])
        XCTAssertEqual(lecturas("venimos"), [rasgos("venir", 1, true, .presente)],
                       "la raíz regular ven- está excluida en el pasado")
        XCTAssertEqual(lecturas("vinimos"), [rasgos("venir", 1, true, .pasado)])
        XCTAssertEqual(lecturas("vinieron"), [rasgos("venir", 3, true, .pasado)])
        XCTAssertEqual(lecturas("vengo"), [rasgos("venir", 1, false, .presente)])
        XCTAssertEqual(lecturas("vino"), [rasgos("venir", 3, false, .pasado)])
    }

    // querer: "quier-" en presente, "quis-" en pasado y "querr-" en futuro.
    func testQuerer() {
        XCTAssertEqual(lecturas("quieren"), [rasgos("querer", 3, true, .presente)])
        XCTAssertEqual(lecturas("quisieron"), [rasgos("querer", 3, true, .pasado)])
        XCTAssertEqual(lecturas("querrán"), [rasgos("querer", 3, true, .futuro)])
        XCTAssertEqual(lecturas("quiso"), [rasgos("querer", 3, false, .pasado)])
    }

    // ser y estar: ser es supletivo; estar es regular salvo "estuv-" en el pasado.
    func testSerYEstar() {
        XCTAssertEqual(lecturas("somos"), [rasgos("ser", 1, true, .presente)])
        XCTAssertEqual(lecturas("es"), [rasgos("ser", 3, false, .presente)])
        XCTAssertEqual(lecturas("seremos"), [rasgos("ser", 1, true, .futuro)])
        XCTAssertEqual(lecturas("están"), [rasgos("estar", 3, true, .presente)])
        XCTAssertEqual(lecturas("estamos"), [rasgos("estar", 1, true, .presente)],
                       "la raíz regular est- está excluida en el pasado")
        XCTAssertEqual(lecturas("estuvieron"), [rasgos("estar", 3, true, .pasado)])
        XCTAssertEqual(lecturas("estoy"), [rasgos("estar", 1, false, .presente)])
    }

    // ir: presente supletivo, futuro regular sobre el infinitivo "ir" de vocab_es.
    func testIr() {
        let van = morfologia.analizarVerbo("van")
        XCTAssertEqual(van.map(\.rasgos), [rasgos("ir", 3, true, .presente)])
        XCTAssertEqual(van.first?.procedencia, .supletiva)
        XCTAssertNil(van.first?.terminacion)
        XCTAssertEqual(lecturas("vamos"), [rasgos("ir", 1, true, .presente)])
        XCTAssertEqual(lecturas("iremos"), [rasgos("ir", 1, true, .futuro)])
    }

    // "fue" es de ser y de ir: los dos candidatos, en el orden de los datos.
    func testFueEsAmbiguaEntreSerEIr() {
        XCTAssertEqual(lecturas("fue"), [rasgos("ser", 3, false, .pasado), rasgos("ir", 3, false, .pasado)])
        XCTAssertEqual(lecturas("fueron").map(\.raiz), ["ser", "ir"])
    }

    // ver: casi regular (v-er); solo "veo" es supletiva.
    func testVer() {
        XCTAssertEqual(lecturas("vimos"), [rasgos("ver", 1, true, .pasado)])
        XCTAssertEqual(lecturas("vieron"), [rasgos("ver", 3, true, .pasado)])
        XCTAssertEqual(lecturas("ven"), [rasgos("ver", 3, true, .presente)])
        XCTAssertEqual(lecturas("veo"), [rasgos("ver", 1, false, .presente)])
        XCTAssertEqual(lecturas("verán"), [rasgos("ver", 3, true, .futuro)])
    }

    // llegar: "llegu-" solo para "llegué".
    func testLlegueUsaSuRaizDelPasado() {
        XCTAssertEqual(lecturas("llegué"), [rasgos("llegar", 1, false, .pasado)])
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

    // MARK: - Infinitivos

    func testInfinitivosConocidos() {
        XCTAssertEqual(morfologia.infinitivo("llegar"), "llegar")
        XCTAssertEqual(morfologia.infinitivo("ir"), "ir", "ir no está en el léxico pero sí en vocab_es")
        XCTAssertEqual(morfologia.infinitivo("VENIR"), "venir")
        XCTAssertNil(morfologia.infinitivo("llegan"))
        XCTAssertNil(morfologia.infinitivo("caminar"))
        XCTAssertNil(morfologia.infinitivo("nave"))
    }

    // MARK: - Sustantivos

    func testPluralDeSustantivos() {
        XCTAssertEqual(morfologia.analizarSustantivo("naves"), [AnalisisNominal(lema: "nave", plural: true)])
        XCTAssertEqual(morfologia.analizarSustantivo("mensajes"), [AnalisisNominal(lema: "mensaje", plural: true)])
        XCTAssertEqual(morfologia.analizarSustantivo("hogares"), [AnalisisNominal(lema: "hogar", plural: true)])
        XCTAssertEqual(morfologia.analizarSustantivo("luces"), [AnalisisNominal(lema: "luz", plural: true)])
        XCTAssertEqual(morfologia.analizarSustantivo("años"), [AnalisisNominal(lema: "año", plural: true)])
    }

    func testSingularDeSustantivos() {
        XCTAssertEqual(morfologia.analizarSustantivo("paz"), [AnalisisNominal(lema: "paz", plural: false)])
        XCTAssertEqual(morfologia.analizarSustantivo("Planeta"), [AnalisisNominal(lema: "planeta", plural: false)])
        XCTAssertEqual(morfologia.analizarSustantivo("llegan"), [])
        XCTAssertEqual(morfologia.analizarSustantivo("casas"), [], "casa no está en el léxico")
    }

    // MARK: - Etiquetado por token

    private func token(_ texto: String, _ columna: Int, _ tipo: TipoToken = .palabra) -> Token {
        Token(tipo: tipo, texto: texto, linea: 1, columna: columna)
    }

    // "van a llegar": cada token lleva su etiqueta; el futuro lo arma el analizador sintáctico.
    func testVanALlegarSeEtiquetaTokenPorToken() {
        let tokens = [token("van", 1), token("a", 5), token("llegar", 7), token("", 13, .fin)]
        let etiquetas = morfologia.etiquetar(tokens)

        XCTAssertEqual(etiquetas.map(\.token.texto), ["van", "a", "llegar"], "el token fin no se analiza")
        XCTAssertEqual(etiquetas[0].verbos.map(\.rasgos), [rasgos("ir", 3, true, .presente)])
        XCTAssertNil(etiquetas[0].infinitivo)
        XCTAssertEqual(etiquetas[1].verbos, [])
        XCTAssertNil(etiquetas[1].infinitivo)
        XCTAssertEqual(etiquetas[2].verbos, [])
        XCTAssertEqual(etiquetas[2].infinitivo, "llegar")
        XCTAssertEqual(etiquetas[2].token.columna, 7, "la posición del token se conserva")
        XCTAssertEqual(Morfologia.texto(etiquetas), "van: ir 3pl presente | a: — | llegar: inf llegar")
    }

    // "¿Cuándo llegan?" con los signos y el número como los dejaría el analizador léxico.
    func testSoloSeAnalizanLasPalabras() {
        let tokens = [
            token("¿", 1, .interrogacion), token("cuando", 2), token("llegan", 9),
            token("15", 16, .numero(15)), token("?", 18, .interrogacion), token("", 19, .fin),
        ]
        let etiquetas = morfologia.etiquetar(tokens)
        XCTAssertEqual(etiquetas.map(\.token.texto), ["cuando", "llegan"])
        XCTAssertEqual(Morfologia.texto(etiquetas), "cuando: — | llegan: llegar 3pl presente")
    }

    func testEtiquetaAmbiguaYPlural() {
        let etiquetas = morfologia.etiquetar([token("enviamos", 1), token("mensajes", 10)])
        XCTAssertTrue(etiquetas[0].esAmbiguo)
        XCTAssertFalse(etiquetas[1].esAmbiguo)
        XCTAssertEqual(
            Morfologia.texto(etiquetas),
            "enviamos: enviar 1pl presente / enviar 1pl pasado | mensajes: mensaje+pl"
        )
    }

    // MARK: - Para el corrector de P1

    func testReconoceFormasQueNoEstanEnElVocabulario() {
        let vocabulario = MorfologiaTests.bd.vocabularioEspanol()
        for forma in ["llegan", "enviaron", "vendrán", "naves", "estrellas"] {
            XCTAssertFalse(vocabulario.contains(BaseDatos.clave(forma)), "\(forma) no está listada")
            XCTAssertTrue(morfologia.reconoce(forma), "\(forma) se reconoce por la morfología")
        }
    }

    func testReconocePalabrasDelLexicoYDelVocabulario() {
        for forma in ["cuando", "nave", "llegar", "ir", "van", "el", "nuestro", "no", "a", "ustedes", "cuántas"] {
            XCTAssertTrue(morfologia.reconoce(forma), forma)
        }
    }

    func testNoReconoceErroresNiMorfemas() {
        for forma in ["lleagn", "naevs", "caminaron", "-amos", "vendr-", "xyz", ""] {
            XCTAssertFalse(morfologia.reconoce(forma), forma)
        }
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
