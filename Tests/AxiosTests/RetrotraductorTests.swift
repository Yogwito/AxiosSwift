import XCTest
@testable import AxiosCore

final class RetrotraductorTests: XCTestCase {
    private func retro(_ frase: String, _ lengua: Lengua, bd: BaseDatos = bdConVocabularioEspanol, en fecha: Date? = nil) -> String? {
        guard case .success(let r) = Retrotraductor(bd: bd).retrotraducir(frase, desde: lengua, en: fecha) else { return nil }
        return r.texto
    }

    func testKethari() {
        XCTAssertEqual(retro("anir ombraesh salok", .kethari), "nosotros · enviar [pasado] · mensaje [plural]")
        XCTAssertEqual(retro("anul parn thal", .kethari), "nosotros incluyente · querer · paz")
        XCTAssertEqual(retro("anir ulesh nukorok", .kethari), "nosotros · no ver [pasado] · ustedes")
    }

    func testKethariPreguntas() {
        XCTAssertEqual(retro("kom ulesh vinime ka", .kethari), "¿cuándo · ustedes · llegar/venir [futuro]?")
        XCTAssertEqual(retro("sem ombra salok ka", .kethari), "¿quién · enviar [pasado] · mensaje?")
    }

    func testKethariNumerosEnBaseSeis() {
        XCTAssertEqual(retro("ra-sel kumesh vinok", .kethari), "15 nave · llegar/venir [pasado]")
        XCTAssertEqual(retro("anul ti-vo lunesh tepime", .kethari), "nosotros incluyente · esperar [futuro] · 6 ciclo")
    }

    func testOzh() {
        XCTAssertEqual(retro("lom tho oruvi ilu", .ozh), "ellas/ellos · querer · paz [tho]")
        XCTAssertEqual(retro("ne ʔim zi ʔenka gor", .ozh), "nosotros/nosotros incluyente · no ver · nave [zi]")
        XCTAssertEqual(retro("ʔoka dra zi ʔenka vesh", .ozh), "nosotros/nosotros incluyente · enviar [pasado] · mensaje [zi]")
    }

    func testOzhPreguntaYNumero() {
        XCTAssertEqual(retro("ʔasur mar shavi wem", .ozh), "¿cuándo · ustedes · llegar/venir [mar]?")
        XCTAssertEqual(retro("venu sur tho ois-ulo gor", .ozh), "15 nave · llegar/venir [futuro] [tho]")
    }

    func testPoseedor() {
        XCTAssertEqual(
            retro("ʔoka kesh zi oruvi thüm ʔenka", .ozh),
            "ellas/ellos · visitar [pasado] · mundo/planeta de nosotros/nosotros incluyente [zi]"
        )
    }

    func testDevuelveLaEstructuraDelValidador() {
        guard case .success(let r) = Retrotraductor(bd: bdConVocabularioEspanol).retrotraducir("kom ulesh vinime ka", desde: .kethari)
        else { return XCTFail() }
        XCTAssertEqual(r.estructura, "[INT kom] [S ulesh] [V vinime] [PREG]")
    }

    func testUnaFraseQueNoValidaNoSeRetrotraduce() {
        let r = Retrotraductor(bd: bdConVocabularioEspanol).retrotraducir("an#dahl thal", desde: .kethari)
        guard case .failure(let e) = r else { return XCTFail("no se lee lo que no se entiende") }
        XCTAssertEqual(e.columna, 3)
    }

    func testSoloDesdeKethariUOzh() {
        guard case .failure = Retrotraductor(bd: bdConVocabularioEspanol).retrotraducir("hola", desde: .es) else {
            return XCTFail()
        }
    }

    /// "Qué se creía en ese momento que significaba cada palabra" (corrección de la semana 2).
    func testSignificadoSegunLaFecha() throws {
        let antes = Date(timeIntervalSince1970: 1_763_467_200)
        let despues = Date(timeIntervalSince1970: 1_764_072_000)
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { antes }
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt"] {
            _ = try bd.cargar(archivo: archivoDatos(archivo))
        }
        bd.reloj = { despues }
        _ = try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))

        let frase = "iresh tekaesh nuthal"
        XCTAssertEqual(retro(frase, .kethari, bd: bd), "ellas/ellos · no querer · territorio reclamado [plural]")
        XCTAssertEqual(retro(frase, .kethari, bd: bd, en: antes), "ellas/ellos · no querer · tierra [plural]")
    }

    func testPartesDeLaEstructura() {
        let partes = Retrotraductor.partes("[T ʔoka] [V kesh] [O thüm ʔenka] [PREG]")
        XCTAssertEqual(partes.map(\.etiqueta), ["T", "V", "O", "PREG"])
        XCTAssertEqual(partes.map(\.palabras), [["ʔoka"], ["kesh"], ["thüm", "ʔenka"], []])
    }
}
