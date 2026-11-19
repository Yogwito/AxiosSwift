import XCTest
import Foundation
@testable import AxiosCore

final class BaseDatosTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let t2 = Date(timeIntervalSince1970: 3_000_000)

    private func nuevaBD(en fecha: Date) throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { fecha }
        return bd
    }

    // MARK: - Clave

    func testClave() {
        XCTAssertEqual(BaseDatos.clave("CUÁNDO"), "cuando")
        XCTAssertEqual(BaseDatos.clave("Año"), "año")
        XCTAssertEqual(BaseDatos.clave(" Él "), "el")
    }

    // MARK: - Apertura

    func testAbreEnMemoriaConLasSieteTablas() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        XCTAssertEqual(try bd.tablas(), [
            "carga", "lexico", "regla", "senal", "senal_palabra", "vocab_es", "pregunta",
        ])
    }

    func testArchivoPersisteAlReabrir() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: url) }
        let ruta = rutaSistema(url)

        // Cada conexión vive solo dentro de su bloque: al salir, deinit cierra la BD.
        // En Windows un archivo abierto no se puede borrar, así que se cierra antes.
        do {
            let bd = try BaseDatos(ruta: ruta)
            try bd.insertarLexico(es: "nave", lengua: .kethari, forma: "kum", categoria: "sustantivo", cargaId: nil)
        }
        do {
            let reabierta = try BaseDatos(ruta: ruta)
            XCTAssertEqual(reabierta.traduccion(es: "nave", lengua: .kethari, en: nil), "kum")
        }

        // Con las dos conexiones cerradas el borrado debe funcionar en todos los SO.
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse((try? url.checkResourceIsReachable()) == true)
    }

    // MARK: - Léxico

    func testInsertarYTraducir() throws {
        let bd = try nuevaBD(en: t0)
        try bd.insertarLexico(es: "nave", lengua: .kethari, forma: "kum", categoria: "sustantivo", cargaId: nil)

        XCTAssertEqual(bd.traduccion(es: "nave", lengua: .kethari, en: nil), "kum")
        XCTAssertEqual(bd.traduccion(es: "NAVE", lengua: .kethari, en: nil), "kum")
        XCTAssertNil(bd.traduccion(es: "telescopio", lengua: .kethari, en: nil))
    }

    func testInsertarDosVecesDejaUnaFila() throws {
        let bd = try nuevaBD(en: t0)
        XCTAssertTrue(try bd.insertarLexico(es: "nave", lengua: .kethari, forma: "kum", categoria: "sustantivo", cargaId: nil))
        XCTAssertFalse(try bd.insertarLexico(es: "nave", lengua: .kethari, forma: "kum", categoria: "sustantivo", cargaId: nil))
        XCTAssertEqual(try bd.contarFilas("lexico"), 1)
    }

    func testInsertarLexicoEnEspanolFalla() throws {
        let bd = try nuevaBD(en: t0)
        XCTAssertThrowsError(
            try bd.insertarLexico(es: "nave", lengua: .es, forma: "nave", categoria: nil, cargaId: nil)
        ) { error in
            guard case ErrorBD.sql = error else {
                return XCTFail("se esperaba ErrorBD.sql, llegó \(error)")
            }
        }
    }

    // MARK: - Versiones (rúbrica #18)

    func testVersionesDelSignificado() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }

        try bd.insertarLexico(es: "tierra", lengua: .kethari, forma: "teka", categoria: "sustantivo", cargaId: nil)
        try bd.insertarLexico(es: "tierra", lengua: .ozh, forma: "mak", categoria: "sustantivo", cargaId: nil)

        ahora = t1
        let resultado = try bd.corregirSignificado(
            lengua: .kethari, forma: "teka", anterior: "tierra", nuevo: "territorio reclamado", cargaId: nil
        )
        XCTAssertEqual(resultado, .aplicada)

        let antes = t0.addingTimeInterval(1)
        XCTAssertNil(bd.traduccion(es: "tierra", lengua: .kethari, en: nil))
        XCTAssertEqual(bd.traduccion(es: "tierra", lengua: .kethari, en: antes), "teka")
        XCTAssertEqual(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: nil), "teka")
        XCTAssertEqual(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: t2), "teka")
        XCTAssertNil(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: antes))

        XCTAssertEqual(bd.significados(forma: "teka", lengua: .kethari, en: antes), ["tierra"])
        XCTAssertEqual(bd.significados(forma: "teka", lengua: .kethari, en: nil), ["territorio reclamado"])

        XCTAssertEqual(bd.traduccion(es: "tierra", lengua: .ozh, en: nil), "mak")
        XCTAssertEqual(try bd.contarFilas("lexico"), 3)

        ahora = t2
        let repetida = try bd.corregirSignificado(
            lengua: .kethari, forma: "teka", anterior: "tierra", nuevo: "territorio reclamado", cargaId: nil
        )
        XCTAssertEqual(repetida, .yaAplicada)
        XCTAssertEqual(try bd.contarFilas("lexico"), 3)
    }

    func testCorregirAlgoInexistente() throws {
        let bd = try nuevaBD(en: t0)
        let resultado = try bd.corregirSignificado(
            lengua: .kethari, forma: "zzz", anterior: "nada", nuevo: "otra cosa", cargaId: nil
        )
        XCTAssertEqual(resultado, .noEncontrada)
        XCTAssertEqual(try bd.contarFilas("lexico"), 0)
    }

    // MARK: - Reglas

    func testReglaSeVersiona() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }

        XCTAssertTrue(try bd.insertarRegla(lengua: .kethari, clave: "base", valor: "6", cargaId: nil))
        XCTAssertEqual(bd.regla("base", lengua: .kethari), "6")

        XCTAssertFalse(try bd.insertarRegla(lengua: .kethari, clave: "base", valor: "6", cargaId: nil))
        XCTAssertEqual(try bd.contarFilas("regla"), 1)

        ahora = t1
        XCTAssertTrue(try bd.insertarRegla(lengua: .kethari, clave: "base", valor: "8", cargaId: nil))
        XCTAssertEqual(bd.regla("base", lengua: .kethari), "8")
        XCTAssertEqual(try bd.contarFilas("regla"), 2)
        XCTAssertNil(bd.regla("base", lengua: .ozh))
    }

    // MARK: - Vocabulario y formas

    func testVocabularioEspanol() throws {
        let bd = try nuevaBD(en: t0)
        try bd.insertarLexico(es: "nave", lengua: .kethari, forma: "kum", categoria: "sustantivo", cargaId: nil)
        try bd.insertarLexico(es: "cuándo", lengua: .kethari, forma: "kom", categoria: "interrogativo", cargaId: nil)
        try bd.insertarLexico(es: "año", lengua: .kethari, forma: "sorlun", categoria: "sustantivo", cargaId: nil)

        let vocabulario = bd.vocabularioEspanol()
        XCTAssertTrue(vocabulario.contains("nave"))
        XCTAssertTrue(vocabulario.contains("cuando"))
        XCTAssertTrue(vocabulario.contains("año"))
    }

    func testExisteForma() throws {
        let bd = try nuevaBD(en: t0)
        try bd.insertarLexico(es: "nave", lengua: .kethari, forma: "kum", categoria: "sustantivo", cargaId: nil)
        XCTAssertTrue(bd.existeForma("kum", lengua: .kethari))
        XCTAssertFalse(bd.existeForma("kum", lengua: .ozh))
    }

    // MARK: - Registro de preguntas

    func testRegistrarYLeerPreguntas() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }

        let primera = RegistroPregunta(
            fecha: t0, original: "¿Cuado llegan?", normalizada: "cuando llegan ?",
            correcciones: [Correccion(original: "cuado", corregida: "cuando", distancia: 1)],
            kethari: "kom vinime ka", ozh: nil, validaK: true, validaO: false,
            motivo: "sin traducción ozh", traza: "[entrada] ¿Cuado llegan?"
        )
        let id1 = try bd.registrar(primera)

        ahora = t1
        let id2 = try bd.registrar(RegistroPregunta(fecha: t1, original: "segunda"))
        XCTAssertGreaterThan(id2, id1)

        let todas = bd.preguntas(desde: nil)
        XCTAssertEqual(todas.count, 2)
        var esperada = primera
        esperada.id = id1
        XCTAssertEqual(todas[0], esperada, "ida y vuelta completa, correcciones incluidas")
        XCTAssertEqual(todas[1].correcciones, [])

        let desdeT1 = bd.preguntas(desde: t1)
        XCTAssertEqual(desdeT1.map(\.original), ["segunda"])
        XCTAssertEqual(bd.preguntas(desde: t2), [])
    }

    func testHistorialPalabraIncluyeFilasCerradas() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }
        let carga = try bd.crearCarga(archivo: "lexico_v0.7.txt", tipo: "lexico", version: "0.7")
        try bd.insertarLexico(es: "tierra", lengua: .kethari, forma: "teka", categoria: "sustantivo", cargaId: carga)
        try bd.insertarLexico(es: "tierra", lengua: .ozh, forma: "mak", categoria: "sustantivo", cargaId: carga)
        ahora = t1
        _ = try bd.corregirSignificado(
            lengua: .kethari, forma: "teka", anterior: "tierra", nuevo: "territorio reclamado", cargaId: nil
        )

        let porForma = bd.historialPalabra("teka")
        XCTAssertEqual(porForma.map(\.es), ["tierra", "territorio reclamado"])
        XCTAssertEqual(porForma[0].vigenteHasta, t1)
        XCTAssertEqual(porForma[0].archivo, "lexico_v0.7.txt")
        XCTAssertNil(porForma[1].vigenteHasta)
        XCTAssertNil(porForma[1].archivo)

        let porEspanol = bd.historialPalabra("TIERRA")
        XCTAssertEqual(porEspanol.map(\.lengua), [.kethari, .ozh])
    }
}
