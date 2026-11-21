import XCTest
@testable import AxiosCore

/// Construye a mano los árboles de frases del enunciado y de las señales, tal como
/// los entregará el analizador sintáctico a los generadores.
final class ArbolIntermedioTests: XCTestCase {
    private func verbo(
        _ raiz: String, _ persona: Int, plural: Bool, _ tiempo: Tiempo,
        polaridad: Polaridad = .afirmativa, perifrastico: Bool = false
    ) -> NodoVerbo {
        NodoVerbo(
            rasgos: RasgosVerbo(raiz: raiz, persona: persona, plural: plural, tiempo: tiempo),
            polaridad: polaridad, perifrastico: perifrastico
        )
    }

    // "¿Cuándo llegan?": pregunta parcial con sujeto omitido.
    func testCuandoLleganTieneSujetoOmitido() {
        let cuando = Interrogativo(lema: "cuando", funcion: .circunstancial)
        let o = Oracion(tipo: .preguntaParcial(cuando), sujeto: .omitido, verbo: verbo("llegar", 3, plural: true, .presente))

        XCTAssertEqual(o.interrogativo, cuando)
        XCTAssertEqual(o.sujeto, .omitido)
        XCTAssertNil(o.objeto)
        XCTAssertEqual(o.verbo.rasgos.persona, 3)
        XCTAssertTrue(o.verbo.rasgos.plural)
        XCTAssertEqual(
            o.texto(),
            "parcial(cuando, circunstancial) · S: omitido · V: llegar 3pl presente · O: —"
        )
    }

    // "Queremos paz": declarativa corta, primera persona plural sin pronombre.
    func testQueremosPazEsDeclarativaConObjeto() {
        let o = Oracion(
            tipo: .declarativa, sujeto: .omitido,
            verbo: verbo("querer", 1, plural: true, .presente),
            objeto: SN(nucleo: .sustantivo(lema: "paz", plural: false))
        )
        XCTAssertNil(o.interrogativo)
        XCTAssertEqual(o.objeto?.plural, false)
        XCTAssertEqual(o.texto(), "declarativa · S: omitido · V: querer 1pl presente · O: paz")
    }

    // "¿Vienen ustedes?": pregunta de sí o no con sujeto explícito.
    func testPreguntaSiNoNoTieneInterrogativo() {
        let ustedes = Pronombre(lema: "ustedes", persona: 2, plural: true)
        let o = Oracion(
            tipo: .preguntaSiNo, sujeto: .explicito(SN(nucleo: .pronombre(ustedes))),
            verbo: verbo("venir", 2, plural: true, .presente)
        )
        XCTAssertNil(o.interrogativo)
        XCTAssertEqual(o.texto(), "pregunta sí/no · S: pron(ustedes) · V: venir 2pl presente · O: —")
    }

    // "¿Quién envió el mensaje?" (señal 6): el interrogativo es el sujeto y el artículo no se guarda.
    func testQuienEsSujetoInterrogativo() {
        let o = Oracion(
            tipo: .preguntaParcial(Interrogativo(lema: "quien", funcion: .sujeto)),
            sujeto: .interrogativo,
            verbo: verbo("enviar", 3, plural: false, .pasado),
            objeto: SN(nucleo: .sustantivo(lema: "mensaje", plural: false))
        )
        XCTAssertEqual(o.interrogativo?.funcion, .sujeto)
        XCTAssertEqual(o.sujeto, .interrogativo)
        XCTAssertEqual(o.objeto, SN(nucleo: .sustantivo(lema: "mensaje", plural: false)))
    }

    // "¿Cuántas naves llegaron?": cuántos pregunta por la cantidad del sujeto, que no lleva número.
    func testCuantosPreguntaPorLaCantidadDelSujeto() {
        let naves = SN(nucleo: .sustantivo(lema: "nave", plural: true))
        let o = Oracion(
            tipo: .preguntaParcial(Interrogativo(lema: "cuantos", funcion: .sujeto)),
            sujeto: .explicito(naves),
            verbo: verbo("llegar", 3, plural: true, .pasado)
        )
        XCTAssertEqual(o.interrogativo?.funcion, .sujeto)
        XCTAssertNil(naves.cantidad)
        XCTAssertTrue(naves.plural)
    }

    // "Quince naves llegaron" (señal 3): la cantidad viene ya convertida a número.
    func testCantidadYPluralDelSustantivo() {
        let naves = SN(nucleo: .sustantivo(lema: "nave", plural: true), cantidad: 15)
        XCTAssertEqual(naves.cantidad, 15)
        XCTAssertTrue(naves.plural)
        XCTAssertEqual(naves.texto(), "15 nave+pl")
    }

    func testCantidadDeCuatroCifras() {
        let anos = SN(nucleo: .sustantivo(lema: "año", plural: true), cantidad: 9_999)
        XCTAssertEqual(anos.cantidad, 9_999)
        XCTAssertEqual(anos.texto(), "9999 año+pl")
    }

    // "nuestro mundo", "su planeta": el poseedor es un pronombre con persona y número.
    func testPosesivosGuardanElPronombreDelPoseedor() {
        let nuestroMundo = SN(
            nucleo: .sustantivo(lema: "mundo", plural: false),
            poseedor: Pronombre(lema: "nosotros", persona: 1, plural: true)
        )
        let suPlaneta = SN(
            nucleo: .sustantivo(lema: "planeta", plural: false),
            poseedor: Pronombre(lema: "el", persona: 3, plural: false)
        )
        XCTAssertEqual(nuestroMundo.poseedor?.lema, "nosotros")
        XCTAssertEqual(nuestroMundo.texto(), "mundo de(nosotros)")
        XCTAssertEqual(suPlaneta.poseedor?.persona, 3)
        XCTAssertFalse(suPlaneta.plural, "el número del SN es el del nombre, no el del poseedor")
    }

    // "Nosotros no los vimos" (señal 4): negación en pasado.
    func testNegacionEnPasado() {
        let v = verbo("ver", 1, plural: true, .pasado, polaridad: .negativa)
        XCTAssertTrue(v.negado)
        XCTAssertEqual(v.texto(), "ver 1pl pasado negativa")
    }

    func testAfirmativaPorDefecto() {
        let v = NodoVerbo(rasgos: RasgosVerbo(raiz: "ver", persona: 1, plural: false, tiempo: .presente))
        XCTAssertEqual(v.polaridad, .afirmativa)
        XCTAssertFalse(v.negado)
        XCTAssertFalse(v.perifrastico)
    }

    // "Van a llegar": el verbo es llegar en futuro; ir solo deja la marca perifrástica.
    func testIrAQuedaComoFuturoDelInfinitivo() {
        let v = verbo("llegar", 3, plural: true, .futuro, perifrastico: true)
        XCTAssertEqual(v.rasgos.raiz, "llegar")
        XCTAssertEqual(v.rasgos.tiempo, .futuro)
        XCTAssertEqual(v.texto(), "llegar 3pl futuro (ir a)")
    }

    // El futuro perifrástico y el simple solo se diferencian por la marca informativa.
    func testFuturoPerifrasticoYSimpleTienenLosMismosRasgos() {
        let llegaran = verbo("llegar", 3, plural: true, .futuro)
        let vanALlegar = verbo("llegar", 3, plural: true, .futuro, perifrastico: true)
        XCTAssertEqual(llegaran.rasgos, vanALlegar.rasgos)
        XCTAssertNotEqual(llegaran, vanALlegar)
    }

    // "nosotros" solo se marca: la forma incluyente o excluyente la elige P3.
    func testPrimeraPluralQuedaMarcada() {
        XCTAssertTrue(Pronombre(lema: "nosotros", persona: 1, plural: true).esPrimeraPlural)
        XCTAssertFalse(Pronombre(lema: "yo", persona: 1, plural: false).esPrimeraPlural)
        XCTAssertFalse(Pronombre(lema: "ustedes", persona: 2, plural: true).esPrimeraPlural)
    }

    func testPronombreComoNucleoDaSuNumero() {
        let ellos = SN(nucleo: .pronombre(Pronombre(lema: "ellos", persona: 3, plural: true)))
        XCTAssertTrue(ellos.plural)
        XCTAssertEqual(ellos.texto(), "pron(ellos)")
    }

    func testArbolesIgualesSonIguales() {
        let a = Oracion(tipo: .declarativa, sujeto: .omitido, verbo: verbo("ver", 1, plural: false, .presente))
        var b = a
        XCTAssertEqual(a, b)
        b.verbo.polaridad = .negativa
        XCTAssertNotEqual(a, b)
    }
}
