import XCTest
import Foundation
@testable import AxiosCore

final class CargadorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let t2 = Date(timeIntervalSince1970: 3_000_000)
    private let t3 = Date(timeIntervalSince1970: 4_000_000)

    private func nuevaBD(en fecha: Date) throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { fecha }
        return bd
    }

    /// Escribe `contenido` en un archivo temporal que se borra al terminar el test.
    private func archivoTemporal(_ contenido: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data(contenido.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Léxico

    func testCargaLexicoV07() throws {
        let bd = try nuevaBD(en: t0)
        let r = try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))

        XCTAssertEqual(r.tipo, .lexico)
        XCTAssertEqual(try bd.versionesCarga(), ["0.7"])
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.nuevas, 96)
        XCTAssertEqual(try bd.contarFilas("lexico"), 96)
        XCTAssertEqual(try bd.contarLexico(lengua: .kethari), 46)
        XCTAssertEqual(try bd.contarLexico(lengua: .ozh), 50)

        XCTAssertEqual(bd.traduccion(es: "nave", lengua: .kethari, en: nil), "kum")
        XCTAssertEqual(bd.traduccion(es: "nave", lengua: .ozh, en: nil), "gor")
        XCTAssertNil(bd.traduccion(es: "6", lengua: .kethari, en: nil))
        XCTAssertEqual(bd.traduccion(es: "6", lengua: .ozh, en: nil), "sab")
        XCTAssertEqual(bd.traduccion(es: "año", lengua: .ozh, en: nil), "drümak")
        XCTAssertEqual(bd.traduccion(es: "cuando", lengua: .kethari, en: nil), "kom")
    }

    func testRecargarLexicoEsIdempotente() throws {
        let bd = try nuevaBD(en: t0)
        try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        let r = try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))

        XCTAssertEqual(r.nuevas, 0)
        XCTAssertEqual(r.omitidas, 96)
        XCTAssertEqual(try bd.contarFilas("lexico"), 96)
    }

    // MARK: - Reglas

    func testCargaReglasV07() throws {
        let bd = try nuevaBD(en: t0)
        let r = try bd.cargar(archivo: archivoDatos("reglas_v0.7.txt"))

        XCTAssertEqual(r.tipo, .reglas)
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.nuevas, 29)
        XCTAssertEqual(try bd.contarFilas("regla"), 29)
        XCTAssertEqual(bd.regla("particula_pregunta", lengua: .ozh), "mar")
        XCTAssertEqual(bd.regla("base", lengua: .kethari), "6")
    }

    // MARK: - Señales

    func testCargaSenalesSemana1() throws {
        let bd = try nuevaBD(en: t0)
        let r = try bd.cargar(archivo: archivoDatos("senales_semana1.txt"))

        XCTAssertEqual(r.tipo, .senales)
        XCTAssertEqual(try bd.versionesCarga(), ["0.7"])
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.nuevas, 15)
        XCTAssertEqual(try bd.contarFilas("senal"), 15)

        let desconocidas = try bd.todasLasSenales().filter { $0.voz == "desconocida" }
        XCTAssertEqual(desconocidas.count, 1)
        XCTAssertEqual(desconocidas.first?.dia, 6)
        XCTAssertEqual(desconocidas.first?.transcripcion, "")
        XCTAssertEqual(desconocidas.first?.salida, "Ya los escuchamos.")

        let conKumesh = bd.senales(conPalabra: "kumesh")
        XCTAssertEqual(conKumesh.count, 1)
        XCTAssertEqual(conKumesh.first?.dia, 3)
        XCTAssertEqual(conKumesh.first?.voz, "kethari")
    }

    func testVersionDeCadaCarga() throws {
        let bd = try nuevaBD(en: t0)
        try bd.cargar(archivo: archivoDatos("senales_semana1.txt"))
        try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        bd.reloj = { self.t1 }
        try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))
        XCTAssertEqual(try bd.versionesCarga(), ["0.7", "0.7", "0.8"])
    }

    func testRecargarSemana1EsIdempotente() throws {
        let bd = try nuevaBD(en: t0)
        try bd.cargar(archivo: archivoDatos("senales_semana1.txt"))
        let r = try bd.cargar(archivo: archivoDatos("senales_semana1.txt"))

        XCTAssertEqual(r.nuevas, 0)
        XCTAssertEqual(r.omitidas, 15)
        XCTAssertEqual(try bd.contarFilas("senal"), 15)
    }

    // MARK: - Tarea 2.6: integración con la corrección de la semana 2

    func testSemana2AplicaLaCorreccion() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }

        try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        try bd.cargar(archivo: archivoDatos("senales_semana1.txt"))

        ahora = t1
        let r = try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))

        XCTAssertEqual(r.tipo, .senales)
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.nuevas, 7, "6 señales + 1 corrección")
        XCTAssertEqual(try bd.contarFilas("senal"), 21)

        XCTAssertNil(bd.traduccion(es: "tierra", lengua: .kethari, en: nil))
        XCTAssertEqual(bd.traduccion(es: "tierra", lengua: .kethari, en: t0), "teka")
        XCTAssertEqual(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: nil), "teka")
        XCTAssertEqual(bd.traduccion(es: "tierra", lengua: .ozh, en: nil), "mak")
        XCTAssertEqual(bd.significados(forma: "teka", lengua: .kethari, en: nil), ["territorio reclamado"])

        let filasLexico = try bd.contarFilas("lexico")
        let otra = try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))
        XCTAssertEqual(otra.nuevas, 0)
        XCTAssertEqual(otra.omitidas, 7, "6 señales repetidas + la corrección ya aplicada")
        XCTAssertEqual(otra.errores, [])
        XCTAssertEqual(try bd.contarFilas("lexico"), filasLexico)
    }

    func testRecargarLexicoNoRevierteLaCorreccion() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }

        try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        ahora = t1
        try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))
        let filasTrasCorreccion = try bd.contarFilas("lexico")

        ahora = t2
        let r = try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))

        XCTAssertEqual(r.nuevas, 0)
        XCTAssertEqual(r.omitidas, 96)
        XCTAssertEqual(r.errores, [])
        XCTAssertNil(bd.traduccion(es: "tierra", lengua: .kethari, en: nil))
        XCTAssertEqual(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: nil), "teka")
        XCTAssertEqual(try bd.contarFilas("lexico"), filasTrasCorreccion, "tierra/teka no se vuelve a insertar")
    }

    func testCorreccionInversaCreaFilaNueva() throws {
        var ahora = t0
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { ahora }

        try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        ahora = t1
        try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))
        ahora = t2
        try bd.cargar(archivo: archivoDatos("lexico_v0.7.txt"))
        let filasAntes = try bd.contarFilas("lexico")

        ahora = t3
        let r = try bd.cargar(archivo: archivoTemporal("CORRECCION|kethari|teka|territorio reclamado|tierra\n"))

        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.nuevas, 1, "la corrección se aplicó")
        XCTAssertEqual(r.omitidas, 0)
        XCTAssertEqual(bd.traduccion(es: "tierra", lengua: .kethari, en: nil), "teka")
        XCTAssertNil(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: nil))
        XCTAssertEqual(bd.traduccion(es: "territorio reclamado", lengua: .kethari, en: t2), "teka")
        XCTAssertEqual(try bd.contarFilas("lexico"), filasAntes + 1)
    }

    // MARK: - Errores de línea

    func testLineasMalasSeReportanYLasBuenasSeCargan() throws {
        let contenido = """
            # señales de prueba · manual versión 0.9
            SENAL|1|kethari|anir ombraesh salok|Nosotros enviamos mensajes.
            SENAL|x|kethari|a b|c
            SENAL|1|ozh

            BASURA
            SENAL|2|ozh|lom tho oruvi ilu|Ellos quieren paz. [tho]

            """
        let bd = try nuevaBD(en: t0)
        let r = try bd.cargar(archivo: archivoTemporal(contenido))

        XCTAssertEqual(r.tipo, .senales)
        XCTAssertEqual(r.nuevas, 2)
        XCTAssertEqual(r.errores.map(\.linea), [3, 4, 6])
        XCTAssertEqual(r.errores.map(\.contenido), ["SENAL|x|kethari|a b|c", "SENAL|1|ozh", "BASURA"])
        XCTAssertTrue(r.errores[0].motivo.contains("día no válido"), r.errores[0].motivo)
        XCTAssertTrue(r.errores[1].motivo.contains("5 campos"), r.errores[1].motivo)
        XCTAssertTrue(r.errores[2].motivo.contains("no reconocida"), r.errores[2].motivo)
        XCTAssertEqual(try bd.contarFilas("senal"), 2)
    }

    func testFinDeLineaWindowsCargaIgual() throws {
        let original = try String(contentsOf: archivoDatos("senales_semana1.txt"), encoding: .utf8)
        let conCRLF = original.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertNotEqual(conCRLF, original)

        let bdLF = try nuevaBD(en: t0)
        let bdCRLF = try nuevaBD(en: t0)
        let rLF = try bdLF.cargar(archivo: archivoDatos("senales_semana1.txt"))
        let rCRLF = try bdCRLF.cargar(archivo: archivoTemporal(conCRLF))

        XCTAssertEqual(rCRLF.tipo, rLF.tipo)
        XCTAssertEqual(rCRLF.nuevas, rLF.nuevas)
        XCTAssertEqual(rCRLF.errores, [])
        XCTAssertEqual(try bdCRLF.versionesCarga(), ["0.7"])
        XCTAssertEqual(bdCRLF.senales(conPalabra: "salok"), bdLF.senales(conPalabra: "salok"))
        XCTAssertEqual(bdCRLF.senales(conPalabra: "drüm").first?.salida, "Yo espero seis ciclos. [mar]")
    }

    func testBOMSeIgnora() throws {
        let bd = try nuevaBD(en: t0)
        let r = try bd.cargar(archivo: archivoTemporal("\u{FEFF}#reglas|version=0.7\nozh|base|10\n"))
        XCTAssertEqual(r.tipo, .reglas)
        XCTAssertEqual(bd.regla("base", lengua: .ozh), "10")
    }

    func testRutaInexistente() throws {
        let bd = try nuevaBD(en: t0)
        let ruta = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        XCTAssertThrowsError(try bd.cargar(archivo: ruta)) { error in
            XCTAssertEqual(error as? ErrorCarga, .archivoNoEncontrado(ruta.path))
        }
    }

    func testNoEsUTF8() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data([0x23, 0x6C, 0xFF, 0xFE, 0x0A]).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let bd = try nuevaBD(en: t0)
        XCTAssertThrowsError(try bd.cargar(archivo: url)) { error in
            XCTAssertEqual(error as? ErrorCarga, .noEsUTF8(url.path))
        }
    }

    func testFormatoDesconocido() throws {
        let bd = try nuevaBD(en: t0)
        let url = try archivoTemporal("hola\nmundo\n")
        XCTAssertThrowsError(try bd.cargar(archivo: url)) { error in
            XCTAssertEqual(error as? ErrorCarga, .formatoDesconocido(url.lastPathComponent))
        }
        XCTAssertEqual(try bd.contarFilas("carga"), 0)
    }

    func testCorreccionDePalabraInexistenteEsErrorDeLinea() throws {
        let bd = try nuevaBD(en: t0)
        let url = try archivoTemporal("CORRECCION|kethari|zzz|nada|algo\n")

        let r = try bd.cargar(archivo: url)
        XCTAssertEqual(r.errores.count, 1)
        XCTAssertEqual(r.errores.first?.linea, 1)
        XCTAssertEqual(r.errores.first?.motivo, "no se encontró 'zzz' = 'nada' vigente en kethari")
        XCTAssertEqual(r.nuevas, 0)
    }

    // MARK: - Registro de cargas

    func testRegistroDeCargas() throws {
        let bd = try nuevaBD(en: t0)
        try bd.cargar(archivo: archivoDatos("reglas_v0.7.txt"))
        try bd.cargar(archivo: archivoTemporal("#lexico|version=0.7\nnave|kum|gor|sustantivo\n|||\n"))

        let cargas = try bd.registrosCarga()
        XCTAssertEqual(cargas.count, 2)
        XCTAssertEqual(cargas[0], BaseDatos.RegistroCarga(tipo: "reglas", filas: 29, errores: nil))
        XCTAssertEqual(cargas[1].tipo, "lexico")
        XCTAssertEqual(cargas[1].filas, 2)
        XCTAssertEqual(cargas[1].errores, "línea 3: falta la palabra en español")
    }
}
