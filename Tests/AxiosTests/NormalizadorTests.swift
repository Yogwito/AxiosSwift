import XCTest
@testable import AxiosCore

final class NormalizadorTests: XCTestCase {
    private let normalizador = Normalizador()

    private func texto(_ entrada: String) -> String {
        normalizador.normalizar(entrada).texto
    }

    func testPasaAMinusculas() {
        XCTAssertEqual(texto("QUEREMOS Paz"), "queremos paz")
    }

    func testQuitaLasTildes() {
        XCTAssertEqual(texto("¿Cuándo vendrán?"), "¿cuando vendran?")
        XCTAssertEqual(texto("ÉL envió un MENSAJE"), "el envio un mensaje")
    }

    func testConservaLaEnie() {
        XCTAssertEqual(texto("AÑO año"), "año año", "sin la ñ, 'año' se confundiría con otra palabra")
    }

    func testQuitaLaDieresis() {
        XCTAssertEqual(texto("pingüino"), "pinguino")
    }

    func testTildeSueltaDeOtroTecladoSeQuita() {
        XCTAssertEqual(texto("cu´ando lleg`an"), "cuando llegan", "la tilde suelta no separa la palabra")
    }

    func testSignosDePreguntaSeConservan() {
        XCTAssertEqual(texto("¿llegan?"), "¿llegan?")
        XCTAssertEqual(texto("cuando llegan"), "cuando llegan", "sin signos también vale")
    }

    func testSignosDePreguntaRepetidosSeReducenAUno() {
        XCTAssertEqual(texto("¿¿llegan???"), "¿llegan?")
    }

    func testOtraPuntuacionSeparaPalabras() {
        XCTAssertEqual(texto("¡Queremos paz!"), "queremos paz")
        XCTAssertEqual(texto("naves,llegan."), "naves llegan")
        XCTAssertEqual(texto("paz... (ya)"), "paz ya")
    }

    func testPuntoDeMilesEntreCifrasSeQuitaSinSeparar() {
        XCTAssertEqual(texto("9.999 naves"), "9999 naves")
        XCTAssertEqual(texto("llegaron 15."), "llegaron 15")
    }

    func testSimbolosQueNoSonPuntuacionSeConservan() {
        XCTAssertEqual(texto("nave$"), "nave$", "el analizador léxico decide si es un error")
    }

    func testColapsaYRecortaEspacios() {
        XCTAssertEqual(texto("  cuando \t llegan \n "), "cuando llegan")
    }

    func testEntradaVacia() {
        XCTAssertEqual(texto(""), "")
        XCTAssertEqual(texto("   "), "")
        XCTAssertEqual(texto("¡!."), "")
    }

    func testCadaCaracterConservaSuColumnaOriginal() {
        let r = normalizador.normalizar("¿CUÁNDO   llegan?")
        XCTAssertEqual(r.texto, "¿cuando llegan?")
        XCTAssertEqual(r.columnas.count, r.texto.count)
        XCTAssertEqual(r.columnaOriginal(1), 1, "¿")
        XCTAssertEqual(r.columnaOriginal(4), 4, "a de cuándo")
        XCTAssertEqual(r.columnaOriginal(9), 11, "la l de llegan, después de tres espacios")
        XCTAssertEqual(r.columnaOriginal(15), 17, "?")
    }

    func testColumnaMasAllaDelFinalEsLaQueSigueAlOriginal() {
        let r = normalizador.normalizar("¿CUÁNDO   llegan?")
        XCTAssertEqual(r.columnaOriginal(16), 18)
        XCTAssertEqual(normalizador.normalizar("").columnaOriginal(1), 1)
    }

    func testColumnasConPuntuacionQuitada() {
        let r = normalizador.normalizar("¡nave!")
        XCTAssertEqual(r.texto, "nave")
        XCTAssertEqual(r.columnaOriginal(1), 2, "la n estaba detrás del ¡")
    }
}
