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

    // MARK: - Carga de vocab_es_v0.7.txt

    private func bdConVocabulario() throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { Date(timeIntervalSince1970: 1_000_000) }
        _ = try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        _ = try bd.cargar(archivo: archivoDatos("vocab_es_v0.7.txt"))
        return bd
    }

    /// Las filas del archivo, leídas directamente (sin pasar por la BD).
    private func filasDelArchivo() throws -> [EntradaVocab] {
        let texto = try String(contentsOf: archivoDatos("vocab_es_v0.7.txt"), encoding: .utf8)
        return texto.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { linea in
                let c = linea.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                return EntradaVocab(fila: c[0], lema: c[1], categoria: c[2], rasgos: c[3])
            }
    }

    /// vocab_es tiene UNIQUE (forma, categoria) con INSERT OR IGNORE: una fila repetida
    /// se perdería en silencio. Ninguna fila del archivo puede quedar omitida.
    func testCargadorAceptaLasCategoriasNuevasSinOmitirFilas() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        let r = try bd.cargar(archivo: archivoDatos("vocab_es_v0.7.txt"))
        XCTAssertEqual(r.tipo, .vocabEs)
        XCTAssertEqual(r.version, "0.7")
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.omitidas, 0)
        XCTAssertEqual(r.nuevas, 116)
        XCTAssertEqual(try bd.contarFilas("vocab_es"), 116)
    }

    func testRecargarVocabEsEsIdempotente() throws {
        let bd = try bdConVocabulario()
        let r = try bd.cargar(archivo: archivoDatos("vocab_es_v0.7.txt"))
        XCTAssertEqual(r.nuevas, 0)
        XCTAssertEqual(r.omitidas, 116)
        XCTAssertEqual(try bd.contarFilas("vocab_es"), 116)
    }

    func testEntradasEspanolIgnoraTildes() throws {
        let bd = try bdConVocabulario()
        // "-an" sin tilde encuentra la del presente y la del futuro ("-án").
        let an = bd.entradasEspanol(forma: "-an")
        XCTAssertEqual(an.map(\.categoria), ["terminacion_presente", "terminacion_futuro"])
        XCTAssertEqual(an[1].rasgos["base"], "infinitivo")

        let el = bd.entradasEspanol(forma: "ÉL").map(\.categoria)
        XCTAssertEqual(Set(el), ["pronombre", "articulo"], "sin tildes 'él' y 'el' coinciden: decide el analizador")
    }

    func testEntradasEspanolDevuelveLosCandidatos() throws {
        let bd = try bdConVocabulario()
        let fue = bd.entradasEspanol(forma: "fue")
        XCTAssertEqual(fue.count, 1)
        XCTAssertEqual(fue[0].lemas, ["ser", "ir"])
        XCTAssertEqual(fue[0].rasgos, ["p": "3", "n": "sg", "t": "pasado"])

        let su = bd.entradasEspanol(forma: "su")
        XCTAssertEqual(su.first?.lemas.first, "el", "el primer candidato es el que se usa por defecto")
        XCTAssertEqual(bd.entradasEspanol(forma: "inexistente"), [])
    }

    func testUstedesEsSegundaPersonaQueConcuerdaEnTercera() throws {
        let bd = try bdConVocabulario()
        let ustedes = try XCTUnwrap(bd.entradasEspanol(forma: "ustedes").first)
        XCTAssertEqual(ustedes.rasgos, ["p": "2", "n": "pl", "pv": "3"])
    }

    func testMorfemasNoEntranAlVocabularioDelCorrector() throws {
        let vocabulario = try bdConVocabulario().vocabularioEspanol()
        XCTAssertFalse(vocabulario.contains("-amos"))
        XCTAssertFalse(vocabulario.contains("vendr-"))
        XCTAssertFalse(vocabulario.contains { $0.contains("-") })
        // Las formas completas sí son palabras.
        for palabra in ["van", "fueron", "nuestro", "el", "no", "cuantas", "nave", "cuando"] {
            XCTAssertTrue(vocabulario.contains(palabra), palabra)
        }
    }

    // MARK: - Coherencia de los datos

    /// Cada terminación verbal declara persona, número, tiempo y base, y su categoría
    /// lleva el mismo tiempo que el rasgo t.
    func testTerminacionesDeclaranSuTiempo() throws {
        let terminaciones = try filasDelArchivo().filter {
            ($0.categoria ?? "").hasPrefix("terminacion_") && $0.categoria != "terminacion_plural"
        }
        XCTAssertEqual(terminaciones.count, 25)
        for t in terminaciones {
            let tiempo = try XCTUnwrap(t.rasgos["t"], t.forma)
            XCTAssertNotNil(Tiempo(rawValue: tiempo), t.forma)
            XCTAssertEqual(t.categoria, "terminacion_\(tiempo)", t.forma)
            XCTAssertNotNil(t.rasgos["p"], t.forma)
            XCTAssertNotNil(t.rasgos["n"], t.forma)
            XCTAssertTrue(["raiz", "infinitivo"].contains(t.rasgos["base"] ?? ""), t.forma)
            XCTAssertTrue(t.forma.hasPrefix("-"), t.forma)
            XCTAssertFalse(t.lemas.isEmpty, t.forma)
        }
    }

    /// Todo lema verbal (de raíces irregulares o excluidas y de formas supletivas) es
    /// un verbo conocido: está en el léxico como verbo o en vocab_es como infinitivo.
    func testLosLemasVerbalesSonVerbosConocidos() throws {
        let bd = try bdConVocabulario()
        func esVerbo(_ lema: String) -> Bool {
            bd.categoria(forma: lema, lengua: .es) == "verbo"
                || bd.entradasEspanol(forma: lema).contains { $0.categoria == "infinitivo" }
        }
        let verbales = try filasDelArchivo().filter {
            ["verbo", "raiz_irregular", "raiz_excluida"].contains($0.categoria ?? "")
        }
        XCTAssertEqual(verbales.count, 35)
        for fila in verbales {
            XCTAssertNotNil(Tiempo(rawValue: fila.rasgos["t"] ?? ""), fila.forma)
            for lema in fila.lemas {
                XCTAssertTrue(esVerbo(lema), "\(fila.forma) → \(lema)")
            }
        }
        for raiz in verbales where raiz.categoria != "verbo" {
            XCTAssertTrue(raiz.forma.hasSuffix("-"), raiz.forma)
        }
    }

    /// El lema de cada posesivo es un pronombre del vocabulario, de donde salen su
    /// persona y su número.
    func testLosPosesivosApuntanAPronombres() throws {
        let bd = try bdConVocabulario()
        let posesivos = try filasDelArchivo().filter { $0.categoria == "posesivo" }
        XCTAssertEqual(posesivos.count, 10)
        for posesivo in posesivos {
            for lema in posesivo.lemas {
                let pronombre = bd.entradasEspanol(forma: lema).first { $0.categoria == "pronombre" }
                XCTAssertNotNil(pronombre?.rasgos["p"], "\(posesivo.forma) → \(lema)")
            }
        }
    }

    /// Cada interrogativo dice qué pregunta (rasgo f, regla R5) y su lema es un
    /// interrogativo del léxico; y cada interrogativo del léxico tiene su fila.
    func testLosInterrogativosDeclaranSuFuncion() throws {
        let bd = try bdConVocabulario()
        let interrogativos = try filasDelArchivo().filter { $0.categoria == "interrogativo" }
        XCTAssertEqual(interrogativos.count, 9)
        for fila in interrogativos {
            XCTAssertTrue(["sujeto", "objeto", "circunstancial"].contains(fila.rasgos["f"] ?? ""), fila.forma)
            XCTAssertEqual(bd.categoria(forma: fila.lemas.first ?? "", lengua: .es), "interrogativo", fila.forma)
            if fila.rasgos["f"] == "sujeto" {
                XCTAssertNotNil(fila.rasgos["n"], "un interrogativo que puede ser sujeto necesita número: \(fila.forma)")
            }
        }
        for palabra in ["qué", "cuándo", "dónde", "cuántos", "quién"] {
            XCTAssertTrue(interrogativos.contains { $0.forma == BaseDatos.clave(palabra) }, palabra)
        }
    }

    /// Cada verbo del léxico (y cada infinitivo de vocab_es) tiene una fila de
    /// transitividad con un valor válido del rasgo tr (regla R4), y no hay filas de
    /// transitividad para palabras que no son verbos.
    func testCadaVerboDelLexicoDeclaraSuTransitividad() throws {
        let lexico = try String(contentsOf: archivoDatos("lexico_v0.7.txt"), encoding: .utf8)
        let verbosLexico = lexico.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") }
            .map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.count == 4 && $0[3] == "verbo" }
            .map { BaseDatos.clave($0[0]) }
        XCTAssertEqual(verbosLexico.count, 11)
        let filas = try filasDelArchivo()
        let infinitivos = filas.filter { $0.categoria == "infinitivo" }.map(\.forma)
        let transitividad = filas.filter { $0.categoria == "transitividad" }
        for verbo in verbosLexico + infinitivos {
            let fila = transitividad.first { $0.forma == verbo }
            XCTAssertNotNil(fila, "falta la fila de transitividad de \(verbo)")
            XCTAssertTrue(["transitivo", "intransitivo", "copulativo"].contains(fila?.rasgos["tr"] ?? ""), verbo)
            XCTAssertEqual(fila?.lemas, [verbo])
        }
        XCTAssertEqual(Set(transitividad.map(\.forma)), Set(verbosLexico + infinitivos), "solo verbos")
    }

    /// La perífrasis "ir a": su forma es un verbo conocido, su lema una preposición y
    /// sus tiempos t y resultado existen.
    func testLaPerifrasisApuntaAUnVerboYUnaPreposicion() throws {
        let bd = try bdConVocabulario()
        let perifrasis = try filasDelArchivo().filter { $0.categoria == "perifrasis" }
        XCTAssertEqual(perifrasis.count, 1)
        for fila in perifrasis {
            XCTAssertTrue(Morfologia(lexicon: bd).esVerbo(fila.forma), fila.forma)
            for lema in fila.lemas {
                XCTAssertTrue(bd.entradasEspanol(forma: lema).contains { $0.categoria == "preposicion" }, lema)
            }
            XCTAssertNotNil(Tiempo(rawValue: fila.rasgos["t"] ?? ""))
            XCTAssertNotNil(Tiempo(rawValue: fila.rasgos["resultado"] ?? ""))
        }
    }
}
