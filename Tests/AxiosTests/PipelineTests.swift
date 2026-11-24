import XCTest
@testable import AxiosCore

/// La pregunta tal como llega, de punta a punta: P1 → P2 → P3 → P4, con los datos reales.
final class PipelineTests: XCTestCase {
    private func bdCompleta() throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt", "vocab_es_v0.7.txt", "numeros_es_v0.7.txt"] {
            _ = try bd.cargar(archivo: archivoDatos(archivo))
        }
        return bd
    }

    private func traducir(_ pregunta: String, bd: BaseDatos) -> (registro: RegistroPregunta, traza: Traza) {
        var traza = Traza()
        let registro = Pipeline.traducir(pregunta, bd: bd, traza: &traza)
        return (registro, traza)
    }

    func testTieneLaFirmaQueEsperaLaCLI() {
        let traductor: CLI.Traductor = Pipeline.traducir
        _ = traductor
    }

    func testPreguntaConNumeroEnLetrasYPosesivo() throws {
        let r = traducir("¿Cuándo llegarán nuestras cinco naves?", bd: try bdCompleta()).registro
        XCTAssertEqual(r.normalizada, "¿cuando llegaran nuestras 5 naves?")
        XCTAssertEqual(r.kethari, "kom pai anir kumesh vinime ka")
        XCTAssertEqual(r.ozh, "venu ʔasur mar ulo gor ʔenka wem")
        XCTAssertTrue(r.validaK)
        XCTAssertTrue(r.validaO)
        XCTAssertNil(r.motivo)
    }

    func testSinTildesNiSignosDaLoMismo() throws {
        let r = traducir("CUANDO LLEGARAN NUESTRAS CINCO NAVES", bd: try bdCompleta()).registro
        XCTAssertEqual(r.kethari, "kom pai anir kumesh vinime ka")
        XCTAssertEqual(r.ozh, "venu ʔasur mar ulo gor ʔenka wem")
    }

    func testDeclarativaConNumero() throws {
        let r = traducir("Quince naves llegaron.", bd: try bdCompleta()).registro
        XCTAssertEqual(r.kethari, "ra-sel kumesh vinok")
        XCTAssertEqual(r.ozh, "ʔoka sur zi ois-ulo gor")
    }

    func testCorrigeAntesDeTraducir() throws {
        let r = traducir("Ellos visitaron nuestro mumdo", bd: try bdCompleta()).registro
        XCTAssertEqual(r.correcciones, [Correccion(original: "mumdo", corregida: "mundo", distancia: 1)])
        XCTAssertEqual(r.kethari, "iresh anir vael dunok")
        XCTAssertEqual(r.ozh, "ʔoka kesh zi oruvi thüm ʔenka")
    }

    // MARK: - Siempre hay respuesta (condición 1)

    func testErrorLexicoSeRegistraConSuColumna() throws {
        let (r, traza) = traducir("¿Llegan naves$?", bd: try bdCompleta())
        XCTAssertNil(r.kethari)
        XCTAssertNil(r.ozh)
        XCTAssertEqual(r.motivo, "error léxico: columna 14: carácter no válido '$'")
        XCTAssertEqual(traza.fases.last?.nombre, Pipeline.Fase.lexico)
    }

    func testErrorSintacticoSeRegistraConSuColumna() throws {
        let r = traducir("xyzqw llegan", bd: try bdCompleta()).registro
        XCTAssertNil(r.kethari)
        XCTAssertTrue(r.motivo?.hasPrefix("error sintáctico: columna 1:") == true, r.motivo ?? "")
    }

    // MARK: - No se inventa nada (condición 3)

    func testPalabraSinRespaldoNoSeTransmite() throws {
        let bd = try bdCompleta()
        _ = try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))  // teka deja de ser "tierra"

        let r = traducir("queremos tierra", bd: bd).registro
        XCTAssertNil(r.kethari, "Kethari ya no tiene palabra para 'tierra'")
        XCTAssertFalse(r.validaK)
        XCTAssertTrue(r.motivo?.contains("Kethari") == true, r.motivo ?? "")
        XCTAssertTrue(r.motivo?.contains("tierra") == true, r.motivo ?? "")
        XCTAssertNotNil(r.ozh, "en Ozh 'tierra' sigue siendo 'mak'")
        XCTAssertTrue(r.validaO)
    }

    // MARK: - Traza

    func testTrazaTieneTodasLasFasesEnOrden() throws {
        let traza = traducir("¿Cuándo llegarán nuestras cinco naves?", bd: try bdCompleta()).traza
        XCTAssertEqual(traza.fases.map(\.nombre), [
            "normalizacion", "lexico", "correccion",
            "morfologia", "clasificacion", "sintaxis", "arbol",
            "kethari", "ozh", "validacion", "retrotraduccion",
        ])
        let salida = Dictionary(uniqueKeysWithValues: traza.fases.map { ($0.nombre, $0.salida) })
        XCTAssertEqual(salida["normalizacion"], "¿cuando llegaran nuestras 5 naves?")
        XCTAssertEqual(salida["correccion"], "sin cambios")
        XCTAssertTrue(salida["validacion"]?.hasPrefix("kethari: válida") == true, salida["validacion"] ?? "")
        XCTAssertTrue(salida["retrotraduccion"]?.contains("K: ¿cuándo") == true, salida["retrotraduccion"] ?? "")
    }

    func testDesdeLaCLI() throws {
        let bd = try bdCompleta()
        let cli = CLI(
            bd: bd, traductor: Pipeline.traducir, raizDatos: try raizRepo().appendingPathComponent("data"),
            zonaHoraria: TimeZone(identifier: "UTC")!
        )
        let salida = cli.ejecutar(["traducir", "quince naves llegaron", "--traza"])
        XCTAssertTrue(salida.contains("[entrada] quince naves llegaron"), salida)
        XCTAssertTrue(salida.contains("[normalizacion] 15 naves llegaron"), salida)
        XCTAssertTrue(salida.contains("Kethari: ra-sel kumesh vinok   [válida]"), salida)
        XCTAssertTrue(salida.contains("Ozh:     ʔoka sur zi ois-ulo gor   [válida]"), salida)
        XCTAssertTrue(salida.contains("Registrada como #1"), salida)
        XCTAssertTrue(cli.ejecutar(["historial"]).contains("quince naves llegaron"))
    }
}
