import XCTest
import Foundation
@testable import AxiosCore

final class CLITests: XCTestCase {
    // Mediodía UTC: la fecha local es la misma en cualquier zona horaria entre UTC-11 y UTC+11.
    private let t0 = Date(timeIntervalSince1970: 1_763_467_200) // 2025-11-18 12:00 UTC
    private let t1 = Date(timeIntervalSince1970: 1_764_072_000) // 2025-11-25 12:00 UTC

    private func nuevaCLI(traductor: CLI.Traductor? = nil) throws -> (CLI, BaseDatos) {
        let bd = try BaseDatos(ruta: ":memory:")
        bd.reloj = { [t0] in t0 }
        let cli = CLI(bd: bd, traductor: traductor, raizDatos: try raizRepo().appendingPathComponent("data"))
        return (cli, bd)
    }

    // MARK: - Ayuda

    func testSinArgumentosYOrdenDesconocidaMuestranLaAyuda() throws {
        let (cli, _) = try nuevaCLI()
        XCTAssertTrue(cli.ejecutar([]).contains(CLI.ayuda))
        XCTAssertTrue(cli.ejecutar(["ayuda"]).contains(CLI.ayuda))

        let desconocida = cli.ejecutar(["xyz"])
        XCTAssertTrue(desconocida.contains(CLI.ayuda))
        XCTAssertTrue(desconocida.contains("xyz"))
        for orden in ["traducir", "cargar", "inicializar", "historial", "palabra"] {
            XCTAssertTrue(CLI.ayuda.contains(orden), orden)
        }
    }

    // MARK: - inicializar / cargar / palabra

    func testInicializarYPalabraNave() throws {
        let (cli, _) = try nuevaCLI()
        let salida = cli.ejecutar(["inicializar"])
        XCTAssertTrue(salida.contains("lexico_v0.7.txt"), salida)
        XCTAssertTrue(salida.contains("reglas_v0.7.txt"), salida)
        XCTAssertTrue(salida.contains("senales_semana1.txt"), salida)
        XCTAssertFalse(salida.contains("senales_semana2.txt"), salida)
        XCTAssertFalse(salida.contains("Error"), salida)

        let nave = cli.ejecutar(["palabra", "nave"])
        XCTAssertTrue(nave.contains("kum"), nave)
        XCTAssertTrue(nave.contains("gor"), nave)
    }

    func testCargarSemana2YPalabraTeka() throws {
        let (cli, bd) = try nuevaCLI()
        _ = cli.ejecutar(["inicializar"])

        bd.reloj = { [t1] in t1 }
        let semana2 = try raizRepo().appendingPathComponent("data").appendingPathComponent("senales_semana2.txt")
        let carga = cli.ejecutar(["cargar", semana2.path])
        XCTAssertTrue(carga.contains("tipo: senales"), carga)
        XCTAssertTrue(carga.contains("versión: 0.8"), carga)
        XCTAssertTrue(carga.contains("nuevas: 7"), carga)
        XCTAssertTrue(carga.contains("errores: 0"), carga)

        let teka = cli.ejecutar(["palabra", "teka"])
        XCTAssertTrue(teka.contains("español: territorio reclamado"), teka)
        XCTAssertTrue(teka.contains("teka = tierra  [2025-11-18 → 2025-11-25]  (lexico_v0.7.txt)"), teka)
        XCTAssertTrue(teka.contains("teka = territorio reclamado  [2025-11-25 → vigente]  (senales_semana2.txt)"), teka)
        XCTAssertTrue(teka.contains("día 8 kethari: iresh tekaesh nuthal"), teka)
    }

    func testCargarRutaInexistenteNoCrashea() throws {
        let (cli, _) = try nuevaCLI()
        let ruta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let salida = cli.ejecutar(["cargar", ruta])
        XCTAssertTrue(salida.hasPrefix("Error al cargar"), salida)
        XCTAssertTrue(salida.contains("no se encontró el archivo"), salida)

        XCTAssertEqual(cli.ejecutar(["cargar"]), "Uso: cargar <archivo>")
    }

    func testPalabraDesconocida() throws {
        let (cli, _) = try nuevaCLI()
        XCTAssertTrue(cli.ejecutar(["palabra", "telescopio"]).contains("No se sabe nada de 'telescopio'"))
    }

    // MARK: - palabra: señales con variantes de las reglas

    /// CLI con léxico, reglas, semana 1 y semana 2 cargados.
    private func cliCompleta() throws -> CLI {
        let (cli, bd) = try nuevaCLI()
        _ = cli.ejecutar(["inicializar"])
        bd.reloj = { [t1] in t1 }
        let semana2 = try raizRepo().appendingPathComponent("data").appendingPathComponent("senales_semana2.txt")
        _ = cli.ejecutar(["cargar", semana2.path])
        return cli
    }

    /// Líneas de la sección "Señales:" de la salida de `palabra`.
    private func lineasSenales(_ salida: String) -> [String] {
        guard let inicio = salida.range(of: "Señales:\n") else { return [] }
        return salida[inicio.upperBound...].split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    func testPalabraTekaEncuentraElPlural() throws {
        let salida = try cliCompleta().ejecutar(["palabra", "teka"])
        XCTAssertEqual(lineasSenales(salida), ["día 8 kethari: iresh tekaesh nuthal"], salida)
    }

    func testPalabraThalEncuentraLaNegacion() throws {
        let salida = try cliCompleta().ejecutar(["palabra", "thal"])
        XCTAssertEqual(lineasSenales(salida), [
            "día 2 kethari: anul parn thal",
            "día 8 kethari: iresh tekaesh nuthal",
        ], salida)
    }

    func testPalabraIrNoConfundeConIresh() throws {
        let salida = try cliCompleta().ejecutar(["palabra", "ir"])
        XCTAssertEqual(lineasSenales(salida), ["día 9 kethari: ir yorr mi ka"], salida)
        XCTAssertFalse(salida.contains("iresh"), salida)
    }

    func testPalabraAnNoConfundeConAnirNiAnul() throws {
        let salida = try cliCompleta().ejecutar(["palabra", "an"])
        let senales = lineasSenales(salida).filter { $0.contains("kethari") }
        XCTAssertEqual(senales, [], salida)
        XCTAssertFalse(salida.contains("anir"), salida)
        XCTAssertFalse(salida.contains("anul"), salida)
    }

    func testVariantesSalenDeLasReglas() throws {
        let (cli, bd) = try nuevaCLI()
        XCTAssertEqual(bd.variantes(de: "teka", lengua: .kethari), ["teka"], "sin reglas cargadas no hay variantes")

        _ = cli.ejecutar(["inicializar"])
        let variantes = bd.variantes(de: "teka", lengua: .kethari)
        XCTAssertEqual(variantes.count, 8, "forma + 3 sufijos, y las 4 con negación: \(variantes)")
        XCTAssertTrue(variantes.contains("tekaesh"))
        XCTAssertTrue(variantes.contains("nuteka"))
        XCTAssertEqual(bd.variantes(de: "mak", lengua: .ozh), ["mak"], "ozh no tiene sufijos ni prefijo de negación")
        XCTAssertFalse(bd.variantes(de: "ir", lengua: .kethari).contains("iresh"), "iresh es palabra propia del léxico")
    }

    // MARK: - validar

    func testValidar() throws {
        let (cli, _) = try nuevaCLI()
        _ = cli.ejecutar(["inicializar"])

        let valida = cli.ejecutar(["validar", "kethari", "kom ulesh vinime ka"])
        XCTAssertTrue(valida.hasPrefix("válida: "), valida)
        XCTAssertTrue(valida.contains("[INT kom]"), valida)

        let invalida = cli.ejecutar(["validar", "ozh", "lom oruvi ilu"])
        XCTAssertTrue(invalida.hasPrefix("inválida (columna 5): "), invalida)
        XCTAssertTrue(invalida.contains("partícula"), invalida)

        XCTAssertTrue(cli.ejecutar(["validar", "klingon", "x"]).hasPrefix("Uso: validar"))
        XCTAssertTrue(cli.ejecutar(["validar"]).hasPrefix("Uso: validar"))
        XCTAssertTrue(CLI.ayuda.contains("validar"))
    }

    // MARK: - traducir

    func testEtiquetasDeResultado() {
        XCTAssertEqual(CLI.resultado(nil, valida: false), "—   [sin traducción]")
        XCTAssertEqual(CLI.resultado("", valida: true), "—   [sin traducción]")
        XCTAssertEqual(CLI.resultado("kom vinime ka", valida: true), "kom vinime ka   [válida]")
        XCTAssertEqual(CLI.resultado("kom vinime", valida: false), "kom vinime   [rechazada por el validador]")
    }

    func testTraducirConValidadorQueRechazaUnaLengua() throws {
        let falso: CLI.Traductor = { pregunta, bd, _ in
            RegistroPregunta(
                fecha: bd.reloj(), original: pregunta, kethari: "kom vinime ka", ozh: "wem sur",
                validaK: true, validaO: false, motivo: "ozh: falta la partícula de pregunta"
            )
        }
        let (cli, _) = try nuevaCLI(traductor: falso)
        let salida = cli.ejecutar(["traducir", "cuando llegan"])
        XCTAssertTrue(salida.contains("Kethari: kom vinime ka   [válida]"), salida)
        XCTAssertTrue(salida.contains("Ozh:     wem sur   [rechazada por el validador]"), salida)
        XCTAssertTrue(salida.contains("Motivo:  ozh: falta la partícula de pregunta"), salida)
    }

    func testTraducirSinTraductorRegistraYApareceEnHistorial() throws {
        let (cli, bd) = try nuevaCLI()
        let salida = cli.ejecutar(["traducir", "¿Cuándo llegan?"])
        XCTAssertTrue(salida.contains("Kethari: —   [sin traducción]"), salida)
        XCTAssertTrue(salida.contains("Ozh:     —   [sin traducción]"), salida)
        XCTAssertTrue(salida.contains("Motivo:  traductor no integrado todavía"), salida)

        let registradas = bd.preguntas(desde: nil)
        XCTAssertEqual(registradas.count, 1)
        XCTAssertEqual(registradas.first?.original, "¿Cuándo llegan?")
        XCTAssertEqual(registradas.first?.traza, "[entrada] ¿Cuándo llegan?")

        let historial = cli.ejecutar(["historial"])
        XCTAssertTrue(historial.contains("¿Cuándo llegan?"), historial)
        XCTAssertTrue(historial.contains("K: — | O: —"), historial)
        XCTAssertTrue(historial.contains("[traductor no integrado todavía]"), historial)
        XCTAssertTrue(historial.hasPrefix("#1  2025-11-1"), historial)
    }

    func testTraducirVacioSeRegistra() throws {
        let (cli, bd) = try nuevaCLI()
        let salida = cli.ejecutar(["traducir", ""])
        XCTAssertTrue(salida.contains("Motivo:  pregunta vacía"), salida)
        _ = cli.ejecutar(["traducir"])

        let registradas = bd.preguntas(desde: nil)
        XCTAssertEqual(registradas.count, 2)
        XCTAssertEqual(registradas.map(\.motivo), ["pregunta vacía", "pregunta vacía"])
    }

    func testTraducirConTrazaMuestraLasFases() throws {
        let (cli, _) = try nuevaCLI()
        let salida = cli.ejecutar(["traducir", "cuando llegan", "--traza"])
        XCTAssertTrue(salida.hasPrefix("[entrada] cuando llegan"), salida)

        let sinTraza = cli.ejecutar(["traducir", "cuando llegan"])
        XCTAssertFalse(sinTraza.contains("[entrada]"), sinTraza)
    }

    func testTraducirConTraductorFalso() throws {
        let falso: CLI.Traductor = { pregunta, bd, traza in
            traza.agregar(fase: "lexico", salida: "2 tokens")
            return RegistroPregunta(
                fecha: bd.reloj(), original: pregunta, normalizada: "cuando llegan",
                correcciones: [Correccion(original: "cuado", corregida: "cuando", distancia: 1)],
                kethari: "kom vinime ka", ozh: "ʔasur mar wem", validaK: true, validaO: true
            )
        }
        let (cli, bd) = try nuevaCLI(traductor: falso)
        let salida = cli.ejecutar(["traducir", "cuado llegan", "--traza"])

        XCTAssertTrue(salida.contains("[entrada] cuado llegan"), salida)
        XCTAssertTrue(salida.contains("[lexico] 2 tokens"), salida)
        XCTAssertTrue(salida.contains("Kethari: kom vinime ka   [válida]"), salida)
        XCTAssertTrue(salida.contains("Ozh:     ʔasur mar wem   [válida]"), salida)
        XCTAssertFalse(salida.contains("Motivo:"), salida)

        let r = try XCTUnwrap(bd.preguntas(desde: nil).first)
        XCTAssertEqual(r.kethari, "kom vinime ka")
        XCTAssertEqual(r.ozh, "ʔasur mar wem")
        XCTAssertTrue(r.validaK && r.validaO)
        XCTAssertEqual(r.correcciones.first?.corregida, "cuando")
        XCTAssertEqual(r.traza, "[entrada] cuado llegan\n[lexico] 2 tokens")
    }

    // MARK: - historial

    func testHistorialFiltrosYFechaInvalida() throws {
        let (cli, _) = try nuevaCLI()
        XCTAssertEqual(cli.ejecutar(["historial"]), "No hay preguntas registradas.")

        _ = cli.ejecutar(["traducir", "cuando llegan"])
        XCTAssertEqual(cli.ejecutar(["historial", "desde", "2099-01-01"]), "No hay preguntas registradas.")
        XCTAssertTrue(cli.ejecutar(["historial", "desde", "2025-01-01"]).contains("cuando llegan"))

        let ayer = cli.ejecutar(["historial", "desde", "ayer"])
        XCTAssertTrue(ayer.hasPrefix("Fecha no válida: 'ayer'"), ayer)
        XCTAssertTrue(cli.ejecutar(["historial", "desde", "2026-13-45"]).hasPrefix("Fecha no válida"))
        XCTAssertEqual(cli.ejecutar(["historial", "hasta", "2026-01-01"]), "Uso: historial [desde AAAA-MM-DD]")
    }
}
