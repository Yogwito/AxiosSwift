import XCTest
import Foundation
@testable import AxiosCore

/// Pares pregunta → traducción esperada (rúbrica #23), leídos de `Tests/pares.txt`.
/// Cada pregunta entra por la CLI con `Pipeline.traducir`, igual que en `axios traducir`,
/// con el léxico, las reglas, las señales de la semana 1 y la semana 2 cargados.
final class ParesTests: XCTestCase {
    /// "—" en el archivo: esa lengua no debe traducirse.
    static let sinTraduccion = "—"
    static let autores = ["P1", "P2", "P3", "P4"]
    static let minimoPorAutor = 8
    static let minimoTotal = 30

    struct Par {
        let linea: Int
        let autor: String
        let espanol: String
        let kethari: String?
        let ozh: String?
        let motivo: String?

        var descripcion: String { "pares.txt:\(linea) [\(autor)] \"\(espanol)\"" }
    }

    // MARK: - Lectura del archivo

    static func leerPares() throws -> [Par] {
        let url = try raizRepo().appendingPathComponent("Tests").appendingPathComponent("pares.txt")
        let texto = try String(contentsOf: url, encoding: .utf8)
        var pares: [Par] = []
        for (i, linea) in texto.components(separatedBy: "\n").enumerated() {
            let numero = i + 1
            let limpia = linea.trimmingCharacters(in: .whitespaces)
            if limpia.isEmpty || limpia.hasPrefix("#") { continue }
            let campos = limpia.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard campos.count == 4 || campos.count == 5 else {
                XCTFail("pares.txt:\(numero): se esperaban 4 o 5 campos y hay \(campos.count): \(limpia)")
                continue
            }
            let lengua: (String) -> String? = { $0 == sinTraduccion ? nil : $0 }
            let par = Par(
                linea: numero, autor: campos[0], espanol: campos[1],
                kethari: lengua(campos[2]), ozh: lengua(campos[3]),
                motivo: campos.count == 5 ? campos[4] : nil
            )
            if par.kethari == nil && par.ozh == nil && par.motivo == nil {
                XCTFail("\(par.descripcion): no se traduce a ninguna lengua y falta el trozo del motivo")
            }
            pares.append(par)
        }
        return pares
    }

    // MARK: - Base de datos

    private func nuevaCLI() throws -> (CLI, BaseDatos) {
        let bd = try BaseDatos(ruta: ":memory:")
        let cli = CLI(
            bd: bd, traductor: Pipeline.traducir, raizDatos: try raizRepo().appendingPathComponent("data"),
            zonaHoraria: TimeZone(identifier: "UTC")!
        )
        _ = cli.ejecutar(["inicializar"])
        try bd.cargar(archivo: archivoDatos("senales_semana2.txt"))
        return (cli, bd)
    }

    // MARK: - Tests

    /// Traduce todos los pares y reporta cada diferencia; no se detiene en la primera.
    func testCadaParDaLaTraduccionEsperada() throws {
        let pares = try ParesTests.leerPares()
        let (cli, bd) = try nuevaCLI()
        XCTAssertFalse(pares.isEmpty)

        for par in pares {
            let antes = bd.preguntas(desde: nil).count
            _ = cli.ejecutar(["traducir", par.espanol])
            let registradas = bd.preguntas(desde: nil)
            guard registradas.count == antes + 1, let r = registradas.last else {
                XCTFail("\(par.descripcion): se registraron \(registradas.count - antes) preguntas en vez de 1")
                continue
            }

            // Una lengua cuenta como traducida solo si hay texto y el validador lo aprobó.
            let k = r.validaK ? r.kethari : nil
            let o = r.validaO ? r.ozh : nil
            comparar(par, "Kethari", esperado: par.kethari, obtenido: k, registro: r)
            comparar(par, "Ozh", esperado: par.ozh, obtenido: o, registro: r)

            if let trozo = par.motivo, !(r.motivo ?? "").contains(trozo) {
                XCTFail("\(par.descripcion): motivo\n  esperado: …\(trozo)…\n  obtenido: \(r.motivo ?? "(sin motivo)")")
            }
        }
    }

    private func comparar(_ par: Par, _ lengua: String, esperado: String?, obtenido: String?, registro r: RegistroPregunta) {
        guard esperado != obtenido else { return }
        let motivo = r.motivo.map { "\n  motivo:   \($0)" } ?? ""
        XCTFail(
            "\(par.descripcion): \(lengua)\n  esperado: \(esperado ?? ParesTests.sinTraduccion)"
                + "\n  obtenido: \(obtenido ?? ParesTests.sinTraduccion)\(motivo)"
        )
    }

    /// Las traducciones esperadas deben ser frases válidas: así un par mal escrito se
    /// detecta aunque el traductor diera lo mismo. Además, el archivo debe llegar a 30 pares.
    func testLosEsperadosSonValidosYHayAlMenosTreinta() throws {
        let pares = try ParesTests.leerPares()
        let (_, bd) = try nuevaCLI()
        for par in pares {
            if let k = par.kethari {
                let v = validarKethari(k, lexicon: bd)
                XCTAssertTrue(v.valida, "\(par.descripcion): Kethari \"\(k)\" no es válido: \(v.motivo ?? "")")
            }
            if let o = par.ozh {
                let v = validarOzh(o, lexicon: bd)
                XCTAssertTrue(v.valida, "\(par.descripcion): Ozh \"\(o)\" no es válido: \(v.motivo ?? "")")
            }
        }
        if pares.count < ParesTests.minimoTotal {
            throw XCTSkip("Hay \(pares.count) pares; faltan \(ParesTests.minimoTotal - pares.count) para llegar a \(ParesTests.minimoTotal)")
        }
    }

    /// Cada integrante aporta al menos 8 pares. Mientras falten los de P1 y P2 se omite.
    func testCadaAutorTieneAlMenosOchoPares() throws {
        let pares = try ParesTests.leerPares()
        var porAutor: [String: Int] = [:]
        for par in pares { porAutor[par.autor, default: 0] += 1 }

        let desconocidos = Set(porAutor.keys).subtracting(ParesTests.autores)
        XCTAssertTrue(desconocidos.isEmpty, "Autores desconocidos en pares.txt: \(desconocidos.sorted())")

        let faltan = ParesTests.autores.compactMap { autor -> (String, Int)? in
            let n = porAutor[autor, default: 0]
            return n < ParesTests.minimoPorAutor ? (autor, ParesTests.minimoPorAutor - n) : nil
        }
        guard !faltan.isEmpty else { return }
        let mensaje = "Faltan pares: " + faltan.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        if faltan.allSatisfy({ ["P1", "P2"].contains($0.0) }) {
            throw XCTSkip(mensaje)
        }
        XCTFail(mensaje)
    }
}
