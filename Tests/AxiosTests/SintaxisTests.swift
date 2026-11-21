import XCTest
@testable import AxiosCore

/// Analizador sintáctico completo: de los tokens al árbol intermedio.
final class SintaxisTests: XCTestCase {
    let analizador = AnalizadorSintactico(lexicon: bdConVocabularioEspanol)

    func arbol(_ frase: String, file: StaticString = #filePath, line: UInt = #line) throws -> Oracion {
        switch analizador.analizar(tokens(frase)) {
        case .success(let oracion): return oracion
        case .failure(let error):
            XCTFail("'\(frase)' → \(error.texto())", file: file, line: line)
            throw error
        }
    }

    func error(_ frase: String) -> ErrorSintactico? {
        if case .failure(let error) = analizador.analizar(tokens(frase)) { return error }
        return nil
    }

    func verbo(
        _ raiz: String, _ persona: Int, _ plural: Bool, _ tiempo: Tiempo,
        _ polaridad: Polaridad = .afirmativa, perifrastico: Bool = false
    ) -> NodoVerbo {
        NodoVerbo(
            rasgos: RasgosVerbo(raiz: raiz, persona: persona, plural: plural, tiempo: tiempo),
            polaridad: polaridad, perifrastico: perifrastico
        )
    }

    func pronombre(_ lema: String, _ persona: Int, _ plural: Bool) -> SN {
        SN(nucleo: .pronombre(Pronombre(lema: lema, persona: persona, plural: plural)))
    }

    func nombre(_ lema: String, plural: Bool = false, cantidad: Int? = nil, poseedor: Pronombre? = nil) -> SN {
        SN(nucleo: .sustantivo(lema: lema, plural: plural), cantidad: cantidad, poseedor: poseedor)
    }

    // MARK: - Preguntas parciales y sujeto omitido (R5, R7)

    func testCuandoLlegan() throws {
        XCTAssertEqual(try arbol("¿ Cuándo llegan ?"), Oracion(
            tipo: .preguntaParcial(Interrogativo(lema: "cuando", funcion: .circunstancial)),
            sujeto: .omitido,
            verbo: verbo("llegar", 3, true, .presente)
        ))
    }

    func testCuandoLleganSinSignosEsPreguntaParcial() throws {
        XCTAssertEqual(try arbol("cuando llegan"), try arbol("¿ Cuándo llegan ?"))
        XCTAssertEqual(try arbol("Cuándo llegan ?"), try arbol("¿ Cuándo llegan ?"), "un solo signo también vale")
    }

    func testQueQuierenPreguntaPorElObjeto() throws {
        let o = try arbol("¿ Qué quieren ?")
        XCTAssertEqual(o.interrogativo, Interrogativo(lema: "que", funcion: .objeto))
        XCTAssertEqual(o.sujeto, .omitido)
        XCTAssertNil(o.objeto)
    }

    func testDondeEstan() throws {
        let o = try arbol("¿ Dónde están ?")
        XCTAssertEqual(o.interrogativo, Interrogativo(lema: "donde", funcion: .circunstancial))
        XCTAssertEqual(o.verbo, verbo("estar", 3, true, .presente))
    }

    func testCuantasNavesLlegaronPreguntaPorElSujeto() throws {
        XCTAssertEqual(try arbol("¿ Cuántas naves llegaron ?"), Oracion(
            tipo: .preguntaParcial(Interrogativo(lema: "cuantos", funcion: .sujeto)),
            sujeto: .explicito(nombre("nave", plural: true)),
            verbo: verbo("llegar", 3, true, .pasado)
        ))
    }

    func testCuantosCiclosEsperaranUstedesPreguntaPorElObjeto() throws {
        let o = try arbol("¿ Cuántos ciclos esperarán ustedes ?")
        XCTAssertEqual(o.interrogativo?.funcion, .objeto)
        XCTAssertEqual(o.sujeto, .explicito(pronombre("ustedes", 2, true)))
        XCTAssertEqual(o.objeto, nombre("ciclo", plural: true))
    }

    func testQuienEsSujetoYElMensajeEsObjeto() throws {
        XCTAssertEqual(try arbol("¿ Quién envió el mensaje ?"), Oracion(
            tipo: .preguntaParcial(Interrogativo(lema: "quien", funcion: .sujeto)),
            sujeto: .interrogativo,
            verbo: verbo("enviar", 3, false, .pasado),
            objeto: nombre("mensaje")
        ))
    }

    func testAQuienEsObjeto() throws {
        let o = try arbol("¿ A quién escuchan ustedes ?")
        XCTAssertEqual(o.interrogativo, Interrogativo(lema: "quien", funcion: .objeto))
        XCTAssertEqual(o.sujeto, .explicito(pronombre("ustedes", 2, true)))
    }

    // MARK: - Tipo de oración sin signos (R8)

    func testLlegaranQuinceNavesEsDeclarativa() throws {
        // Señal 3, voz Ozh: el decodificador dio "Llegarán quince naves." (afirmación).
        XCTAssertEqual(try arbol("Llegarán 15 naves"), Oracion(
            tipo: .declarativa,
            sujeto: .explicito(nombre("nave", plural: true, cantidad: 15)),
            verbo: verbo("llegar", 3, true, .futuro)
        ))
    }

    func testVienenUstedesSinSignosEsPreguntaSiNo() throws {
        let o = try arbol("vienen ustedes")
        XCTAssertEqual(o.tipo, .preguntaSiNo)
        XCTAssertEqual(o.sujeto, .explicito(pronombre("ustedes", 2, true)))
        XCTAssertEqual(try arbol("¿ Vienen ustedes ?"), o)
    }

    func testUstedesVienenEsDeclarativa() throws {
        XCTAssertEqual(try arbol("Ustedes vienen").tipo, .declarativa)
        XCTAssertEqual(try arbol("¿ Ustedes vienen ?").tipo, .preguntaSiNo, "con signos siempre es pregunta")
    }

    // MARK: - Concordancia y papeles (R3, R4, R6)

    func testQueremosPazTienePazDeObjeto() throws {
        XCTAssertEqual(try arbol("Queremos paz"), Oracion(
            tipo: .declarativa,
            sujeto: .omitido,
            verbo: verbo("querer", 1, true, .presente),
            objeto: nombre("paz")
        ))
    }

    func testUstedesConcuerdaEnTerceraYQuedaEnSegunda() throws {
        let o = try arbol("Ustedes no hablan")
        XCTAssertEqual(o.sujeto, .explicito(pronombre("ustedes", 2, true)), "en el árbol es 2.ª persona")
        XCTAssertEqual(o.verbo, verbo("hablar", 3, true, .presente, .negativa), "el verbo concuerda en 3.ª")
        XCTAssertEqual(error("Ustedes hablamos")?.columna, 9)
    }

    func testEnviamosSinContextoEsPresente() throws {
        XCTAssertEqual(try arbol("Enviamos mensajes").verbo.rasgos.tiempo, .presente)
    }

    func testConcordanciaEligeLaLecturaDelVerbo() throws {
        // "llego" sin tilde es "llego" (1.ª, presente) o "llegó" (3.ª, pasado).
        XCTAssertEqual(try arbol("Yo llego").verbo, verbo("llegar", 1, false, .presente))
        XCTAssertEqual(try arbol("Él llego").verbo, verbo("llegar", 3, false, .pasado))
        XCTAssertEqual(try arbol("llego").verbo, verbo("llegar", 1, false, .presente), "sin sujeto, la primera")
    }

    func testErroresDeConcordanciaConSuColumna() {
        XCTAssertEqual(
            error("Nosotros vienen"),
            ErrorSintactico(motivo: "el sujeto 'Nosotros' no concuerda con el verbo 'vienen'", linea: 1, columna: 10)
        )
        XCTAssertEqual(error("¿ Cuándo ellos llego ?")?.columna, 16)
        XCTAssertEqual(error("Ellos llego")?.motivo, "el sujeto 'Ellos' no concuerda con el verbo 'llego'")
    }

    // MARK: - El / él (R12)

    func testElArticuloYElPronombreSeDistinguenPorContexto() throws {
        let o = try arbol("¿ Es él una criatura ?")
        XCTAssertEqual(o.tipo, .preguntaSiNo)
        XCTAssertEqual(o.sujeto, .explicito(pronombre("el", 3, false)))
        XCTAssertEqual(o.objeto, nombre("criatura"))

        let sinTildes = try arbol("es el una criatura")
        XCTAssertEqual(sinTildes.sujeto, o.sujeto, "sin tilde, 'el' antes de 'una' es el pronombre")

        let articulo = try arbol("El mensaje llegó")
        XCTAssertEqual(articulo.sujeto, .explicito(nombre("mensaje")))
    }

    // MARK: - Cantidades (R1)

    func testCantidadDeCuatroCifras() throws {
        XCTAssertEqual(try arbol("Esperaremos 9999 años").objeto, nombre("año", plural: true, cantidad: 9_999))
        XCTAssertEqual(AnalizadorSintactico.cantidadMaxima, 9_999)
    }

    func testCantidadMayorQueElMaximoEsError() {
        XCTAssertEqual(
            error("Esperaremos 10000 años"),
            ErrorSintactico(motivo: "la cantidad 10000 pasa del máximo de 9999", linea: 1, columna: 13)
        )
    }

    // MARK: - Tiempos, negación, "ir a" y posesivos (R9, R10, R11)

    func testVendranYEnviaron() throws {
        XCTAssertEqual(try arbol("¿ Cuándo vendrán ?").verbo, verbo("venir", 3, true, .futuro))
        XCTAssertEqual(try arbol("Ellos enviaron mensajes").verbo, verbo("enviar", 3, true, .pasado))
    }

    func testVanALlegarEsFuturoPerifrastico() throws {
        XCTAssertEqual(try arbol("Van a llegar"), Oracion(
            tipo: .declarativa,
            sujeto: .omitido,
            verbo: verbo("llegar", 3, true, .futuro, perifrastico: true)
        ))
        XCTAssertEqual(
            try arbol("¿ Cuándo no van a llegar ellos ?").verbo,
            verbo("llegar", 3, true, .futuro, .negativa, perifrastico: true)
        )
    }

    func testIrEnPasadoConASobra() {
        XCTAssertEqual(error("Fueron a ver")?.columna, 8, "\"fueron a ver\" no es un futuro")
    }

    func testPosesivos() throws {
        let o = try arbol("Ellos visitaron nuestro mundo")
        XCTAssertEqual(o.objeto, nombre("mundo", poseedor: Pronombre(lema: "nosotros", persona: 1, plural: true)))
        let su = try arbol("Queremos su planeta")
        XCTAssertEqual(su.objeto?.poseedor, Pronombre(lema: "el", persona: 3, plural: false))
    }

    // MARK: - Errores

    func testPalabraDesconocidaConSuColumna() {
        XCTAssertEqual(
            error("¿ Cuándo xyz ?"),
            ErrorSintactico(motivo: "palabra desconocida 'xyz'", linea: 1, columna: 10)
        )
    }

    func testSinVerboEsError() {
        XCTAssertEqual(error("nave paz")?.motivo, "se esperaba un verbo y llegó 'paz'")
        XCTAssertEqual(error("")?.motivo, "se esperaba un verbo y llegó el final de la frase")
    }

    func testSobraUnSintagma() {
        XCTAssertEqual(
            error("Ellos quieren paz naves"),
            ErrorSintactico(motivo: "sobra 'naves': la oración ya tiene objeto", linea: 1, columna: 19)
        )
        XCTAssertEqual(error("Queremos paz ?  ¿")?.columna, 17)
    }
}
