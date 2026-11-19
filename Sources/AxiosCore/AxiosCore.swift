import CSQLite

/// Versión de SQLite enlazada desde el target CSQLite.
public enum AxiosCore {
    public static var sqliteVersion: String {
        String(cString: sqlite3_libversion())
    }
}
