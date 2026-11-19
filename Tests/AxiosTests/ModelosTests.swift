import XCTest
@testable import AxiosCore

final class ModelosTests: XCTestCase {
    func testTokenGuardaSuPosicion() {
        let token = Token(tipo: .palabra, texto: "llegan", linea: 1, columna: 8)
        XCTAssertEqual(token.texto, "llegan")
        XCTAssertEqual(token.linea, 1)
        XCTAssertEqual(token.columna, 8)
    }

    func testTokenNumeroGuardaElValor() {
        let token = Token(tipo: .numero(15), texto: "15", linea: 1, columna: 1)
        XCTAssertEqual(token.tipo, .numero(15))
    }

    func testRasgosVerbo() {
        let rasgos = RasgosVerbo(raiz: "venir", persona: 3, plural: true, tiempo: .futuro)
        XCTAssertEqual(rasgos.raiz, "venir")
        XCTAssertEqual(rasgos.tiempo, .futuro)
    }

    func testLasLenguasTienenSuNombreEnTexto() {
        XCTAssertEqual(Lengua.kethari.rawValue, "kethari")
        XCTAssertEqual(Lengua.ozh.rawValue, "ozh")
        XCTAssertEqual(Lengua.es.rawValue, "es")
    }

    func testLaTrazaGuardaLasFasesEnOrden() {
        var traza = Traza()
        traza.agregar(fase: "normalizador", salida: "cuando llegan ?")
        traza.agregar(fase: "lexico", salida: "3 tokens")
        XCTAssertEqual(traza.fases.count, 2)
        XCTAssertEqual(traza.fases[0].nombre, "normalizador")
        XCTAssertEqual(traza.fases[1].salida, "3 tokens")
    }

    func testTrazaTextoUnaFasePorLinea() {
        var traza = Traza()
        XCTAssertEqual(traza.texto(), "")

        traza.agregar(fase: "lexico", salida: "3 tokens")
        traza.agregar(fase: "sintaxis", salida: "pregunta válida")

        XCTAssertEqual(traza.fases.count, 2)
        XCTAssertEqual(traza.fases[0], Traza.Fase(nombre: "lexico", salida: "3 tokens"))
        XCTAssertEqual(traza.texto(), "[lexico] 3 tokens\n[sintaxis] pregunta válida")
    }

    func testCorreccionCodableIdaYVuelta() throws {
        let original = Correccion(original: "cuando", corregida: "cuándo", distancia: 1)

        let datos = try JSONEncoder().encode(original)
        let decodificada = try JSONDecoder().decode(Correccion.self, from: datos)

        XCTAssertEqual(decodificada, original)
    }
}
