import XCTest
import Foundation
import CSQLite
@testable import AxiosCore

final class EsquemaTests: XCTestCase {
    private var db: OpaquePointer?

    override func setUpWithError() throws {
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
    }

    override func tearDown() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Ayudantes

    private func esquemaSQL() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "schema", withExtension: "sql"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Ejecuta SQL y devuelve el código de SQLite; el mensaje de error, si hay, va a `error`.
    @discardableResult
    private func ejecutar(_ sql: String, error: inout String?) -> Int32 {
        var mensaje: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &mensaje)
        if let mensaje {
            error = String(cString: mensaje)
            sqlite3_free(mensaje)
        }
        return rc
    }

    private func tablas() throws -> Set<String> {
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var nombres = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            nombres.insert(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return nombres
    }

    /// Filas de datos de un archivo "|": sin líneas vacías ni comentarios "#".
    private func filasDatos(_ nombre: String) throws -> [[String]] {
        let url = try archivoDatos(nombre)
        let contenido = try String(contentsOf: url, encoding: .utf8)
        return contenido
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
    }

    // MARK: - Esquema

    func testEsquemaCreaLasSieteTablas() throws {
        var error: String?
        XCTAssertEqual(ejecutar(try esquemaSQL(), error: &error), SQLITE_OK, error ?? "")
        let esperadas: Set<String> = [
            "carga", "lexico", "regla", "senal", "senal_palabra", "vocab_es", "pregunta",
        ]
        XCTAssertEqual(try tablas(), esperadas)
    }

    func testEsquemaSePuedeEjecutarDosVeces() throws {
        let sql = try esquemaSQL()
        var error: String?
        XCTAssertEqual(ejecutar(sql, error: &error), SQLITE_OK, error ?? "")
        XCTAssertEqual(ejecutar(sql, error: &error), SQLITE_OK, error ?? "")
        XCTAssertEqual(try tablas().count, 7)
    }

    func testLexicoRechazaLenguaEspanol() throws {
        var error: String?
        XCTAssertEqual(ejecutar(try esquemaSQL(), error: &error), SQLITE_OK, error ?? "")

        let rc = ejecutar("""
            INSERT INTO lexico (es, es_clave, lengua, forma, vigente_desde)
            VALUES ('paz', 'paz', 'es', 'paz', 0);
            """, error: &error)
        XCTAssertEqual(rc, SQLITE_CONSTRAINT)
        XCTAssertTrue(error?.contains("CHECK") ?? false, error ?? "sin mensaje")
    }

    // MARK: - Archivos de datos

    func testLexicoV07Tiene50FilasDeCuatroCampos() throws {
        let filas = try filasDatos("lexico_v0.7.txt")
        XCTAssertEqual(filas.count, 50)
        for (i, fila) in filas.enumerated() {
            XCTAssertEqual(fila.count, 4, "fila \(i + 1): \(fila)")
        }
    }

    func testReglasV07Tiene27FilasDeTresCampos() throws {
        let filas = try filasDatos("reglas_v0.7.txt")
        XCTAssertEqual(filas.count, 27)
        for (i, fila) in filas.enumerated() {
            XCTAssertEqual(fila.count, 3, "fila \(i + 1): \(fila)")
        }
    }
}
