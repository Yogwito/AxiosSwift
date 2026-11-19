import XCTest
import CSQLite
@testable import AxiosCore

final class EsqueletoTests: XCTestCase {
    /// Comprueba que el target C CSQLite compila y enlaza en la plataforma actual.
    func testSQLiteEnMemoriaAbre() {
        var db: OpaquePointer?
        let rc = sqlite3_open(":memory:", &db)
        defer { sqlite3_close(db) }
        XCTAssertEqual(rc, SQLITE_OK)
        XCTAssertNotNil(db)
    }

    func testVersionSQLite() {
        XCTAssertFalse(AxiosCore.sqliteVersion.isEmpty)
    }
}
