import Foundation
import CSQLite

public enum ErrorBD: Error, Equatable {
    case apertura(String)
    case sql(String)
    case esquema(String)
}

/// Le indica a SQLite que copie el texto enlazado (el buffer de Swift es temporal).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Acceso a la base de datos SQLite del traductor.
///
/// El léxico y las reglas están versionados: una corrección nunca borra filas,
/// cierra la vigente (`vigente_hasta`) e inserta otra. Las fechas se guardan como
/// REAL con `timeIntervalSince1970`.
public final class BaseDatos: Lexicon {
    private var db: OpaquePointer?

    /// Fuente de "ahora" para todas las fechas que escribe la base de datos.
    /// Los tests la sustituyen para tener fechas fijas.
    public var reloj: () -> Date = Date.init

    // MARK: - Apertura

    /// Abre o crea la base de datos en `ruta` (":memory:" para una en memoria)
    /// y aplica el esquema.
    public init(ruta: String) throws {
        var conexion: OpaquePointer?
        let rc = sqlite3_open_v2(ruta, &conexion, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let conexion else {
            let mensaje = conexion.map { String(cString: sqlite3_errmsg($0)) }
                ?? String(cString: sqlite3_errstr(rc))
            sqlite3_close(conexion)
            throw ErrorBD.apertura(mensaje)
        }
        db = conexion

        try ejecutarScript("PRAGMA foreign_keys = ON;")
        try aplicarEsquema()
    }

    deinit {
        sqlite3_close(db)
    }

    private func aplicarEsquema() throws {
        guard let url = Bundle.module.url(forResource: "schema", withExtension: "sql") else {
            throw ErrorBD.esquema("no se encontró schema.sql en los recursos")
        }
        let sql: String
        do {
            sql = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ErrorBD.esquema("no se pudo leer schema.sql: \(error)")
        }
        do {
            try ejecutarScript(sql)
        } catch let ErrorBD.sql(mensaje) {
            throw ErrorBD.esquema(mensaje)
        }
    }

    // MARK: - Transacciones

    /// Ejecuta `cuerpo` dentro de una transacción: COMMIT si termina bien,
    /// ROLLBACK si lanza. Si ya hay una transacción abierta se usa un SAVEPOINT,
    /// así las llamadas anidadas (por ejemplo, una corrección dentro de una carga) funcionan.
    public func transaccion<T>(_ cuerpo: () throws -> T) throws -> T {
        let anidada = sqlite3_get_autocommit(db) == 0
        try ejecutarScript(anidada ? "SAVEPOINT anidada;" : "BEGIN;")
        do {
            let resultado = try cuerpo()
            try ejecutarScript(anidada ? "RELEASE anidada;" : "COMMIT;")
            return resultado
        } catch {
            try? ejecutarScript(anidada ? "ROLLBACK TO anidada; RELEASE anidada;" : "ROLLBACK;")
            throw error
        }
    }

    // MARK: - Clave normalizada

    /// Clave de búsqueda de una palabra española: minúsculas, sin tildes ni
    /// diéresis (salvo la ñ) y sin espacios al inicio o al final.
    public static func clave(_ s: String) -> String {
        var resultado = ""
        for c in s.lowercased() {
            if c == "ñ" {
                resultado.append(c)
            } else {
                resultado += String(c).folding(options: .diacriticInsensitive, locale: nil)
            }
        }
        return resultado.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Escritura: cargas

    public func crearCarga(archivo: String, tipo: String, version: String?) throws -> Int64 {
        try ejecutar(
            "INSERT INTO carga (archivo, tipo, version_manual, cargada_en) VALUES (?, ?, ?, ?)",
            [.texto(archivo), .texto(tipo), .textoOpcional(version), .real(ahora())]
        )
        return sqlite3_last_insert_rowid(db)
    }

    public func cerrarCarga(id: Int64, filas: Int, errores: [String]) throws {
        try ejecutar(
            "UPDATE carga SET filas = ?, errores = ? WHERE id = ?",
            [
                .entero(Int64(filas)),
                errores.isEmpty ? .nulo : .texto(errores.joined(separator: "\n")),
                .entero(id),
            ]
        )
    }

    // MARK: - Escritura: léxico

    /// Inserta una traducción vigente desde `reloj()`. Si ya existe cualquier fila
    /// (vigente o cerrada) con la misma clave, lengua y forma no hace nada: cargar el
    /// manual solo agrega lo que no se conoce, y un significado cerrado por una
    /// corrección no vuelve al recargar. Cambiar un significado solo se hace con
    /// `corregirSignificado`, que no pasa por esta comprobación.
    /// - Returns: `true` si insertó una fila, `false` si ya se conocía.
    @discardableResult
    public func insertarLexico(
        es: String, lengua: Lengua, forma: String, categoria: String?, cargaId: Int64?
    ) throws -> Bool {
        let claveEs = BaseDatos.clave(es)
        let existe = try consultar(
            """
            SELECT 1 FROM lexico
            WHERE es_clave = ? AND lengua = ? AND forma = ?
            LIMIT 1
            """,
            [.texto(claveEs), .texto(lengua.rawValue), .texto(forma)]
        ) { _ in true }
        guard existe.isEmpty else { return false }

        try ejecutar(
            """
            INSERT INTO lexico (es, es_clave, lengua, forma, categoria, carga_id, vigente_desde)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .texto(es), .texto(claveEs), .texto(lengua.rawValue), .texto(forma),
                .textoOpcional(categoria), .enteroOpcional(cargaId), .real(ahora()),
            ]
        )
        return true
    }

    // MARK: - Escritura: reglas

    /// Fija el valor vigente de una regla. Si ya vale lo mismo no hace nada;
    /// si valía otra cosa cierra la fila anterior e inserta la nueva.
    /// - Returns: `true` si insertó una fila, `false` si ya estaba vigente con ese valor.
    @discardableResult
    public func insertarRegla(lengua: Lengua, clave: String, valor: String, cargaId: Int64?) throws -> Bool {
        try transaccion {
            let vigentes = try consultar(
                "SELECT id, valor FROM regla WHERE lengua = ? AND clave = ? AND vigente_hasta IS NULL",
                [.texto(lengua.rawValue), .texto(clave)]
            ) { fila in (id: entero(fila, 0), valor: texto(fila, 1)) }

            if vigentes.contains(where: { $0.valor == valor }) { return false }

            let momento = ahora()
            for anterior in vigentes {
                try ejecutar(
                    "UPDATE regla SET vigente_hasta = ? WHERE id = ?",
                    [.real(momento), .entero(anterior.id)]
                )
            }
            try ejecutar(
                """
                INSERT INTO regla (lengua, clave, valor, carga_id, vigente_desde)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .texto(lengua.rawValue), .texto(clave), .texto(valor),
                    .enteroOpcional(cargaId), .real(momento),
                ]
            )
            return true
        }
    }

    // MARK: - Escritura: señales y vocabulario

    /// Guarda una señal y sus palabras (en `senal_palabra`, con posición desde 1).
    /// - Returns: `true` si la señal es nueva, `false` si ya existía (mismo día, voz y transcripción).
    @discardableResult
    public func insertarSenal(
        dia: Int, voz: String, transcripcion: String, salida: String?, cargaId: Int64?
    ) throws -> Bool {
        try transaccion {
            try ejecutar(
                """
                INSERT OR IGNORE INTO senal (dia, voz, transcripcion, salida, carga_id)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .entero(Int64(dia)), .texto(voz), .texto(transcripcion),
                    .textoOpcional(salida), .enteroOpcional(cargaId),
                ]
            )
            guard sqlite3_changes(db) > 0 else { return false }

            let senalId = sqlite3_last_insert_rowid(db)
            let palabras = transcripcion.split(whereSeparator: { $0.isWhitespace })
            for (i, palabra) in palabras.enumerated() {
                try ejecutar(
                    "INSERT INTO senal_palabra (senal_id, posicion, forma) VALUES (?, ?, ?)",
                    [.entero(senalId), .entero(Int64(i + 1)), .texto(String(palabra))]
                )
            }
            return true
        }
    }

    /// Agrega una forma al vocabulario español. Si ya existe (misma forma y categoría) no hace nada.
    /// - Returns: `true` si insertó una fila.
    @discardableResult
    public func insertarVocab(forma: String, lema: String?, categoria: String?, rasgos: String?) throws -> Bool {
        try ejecutar(
            "INSERT OR IGNORE INTO vocab_es (forma, lema, categoria, rasgos) VALUES (?, ?, ?, ?)",
            [.texto(forma), .textoOpcional(lema), .textoOpcional(categoria), .textoOpcional(rasgos)]
        )
        return sqlite3_changes(db) > 0
    }

    // MARK: - Escritura: correcciones del manual

    public enum ResultadoCorreccion: Equatable {
        case aplicada
        case yaAplicada
        case noEncontrada
    }

    /// Cambia el significado español de una palabra de `lengua` sin borrar nada:
    /// cierra la fila vigente con el significado `anterior` e inserta otra con `nuevo`.
    public func corregirSignificado(
        lengua: Lengua, forma: String, anterior: String, nuevo: String, cargaId: Int64?
    ) throws -> ResultadoCorreccion {
        try transaccion {
            let vigente = try consultar(
                """
                SELECT id, categoria FROM lexico
                WHERE lengua = ? AND forma = ? AND es_clave = ? AND vigente_hasta IS NULL
                ORDER BY vigente_desde DESC, id DESC
                LIMIT 1
                """,
                [.texto(lengua.rawValue), .texto(forma), .texto(BaseDatos.clave(anterior))]
            ) { fila in (id: entero(fila, 0), categoria: textoOpcional(fila, 1)) }.first

            guard let vigente else {
                let yaEsta = try consultar(
                    """
                    SELECT 1 FROM lexico
                    WHERE lengua = ? AND forma = ? AND es_clave = ? AND vigente_hasta IS NULL
                    LIMIT 1
                    """,
                    [.texto(lengua.rawValue), .texto(forma), .texto(BaseDatos.clave(nuevo))]
                ) { _ in true }
                return yaEsta.isEmpty ? .noEncontrada : .yaAplicada
            }

            let momento = ahora()
            try ejecutar(
                "UPDATE lexico SET vigente_hasta = ? WHERE id = ?",
                [.real(momento), .entero(vigente.id)]
            )
            try ejecutar(
                """
                INSERT INTO lexico (es, es_clave, lengua, forma, categoria, carga_id, vigente_desde)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .texto(nuevo), .texto(BaseDatos.clave(nuevo)), .texto(lengua.rawValue),
                    .texto(forma), .textoOpcional(vigente.categoria), .enteroOpcional(cargaId),
                    .real(momento),
                ]
            )
            return .aplicada
        }
    }

    // MARK: - Lectura (Lexicon)

    /// Condición de vigencia: actual si `fecha` es nil, o la vigente en `fecha`.
    private func vigencia(_ fecha: Date?) -> (sql: String, valores: [Valor]) {
        guard let fecha else { return ("vigente_hasta IS NULL", []) }
        let f = fecha.timeIntervalSince1970
        return ("vigente_desde <= ? AND (vigente_hasta IS NULL OR vigente_hasta > ?)", [.real(f), .real(f)])
    }

    public func traduccion(es: String, lengua: Lengua, en fecha: Date?) -> String? {
        let claveEs = BaseDatos.clave(es)
        let (condicion, valores) = vigencia(fecha)

        if lengua == .es {
            let existe = try? consultar(
                "SELECT 1 FROM lexico WHERE es_clave = ? AND \(condicion) LIMIT 1",
                [.texto(claveEs)] + valores
            ) { _ in true }
            return (existe?.isEmpty == false) ? claveEs : nil
        }

        let formas = try? consultar(
            """
            SELECT forma FROM lexico
            WHERE es_clave = ? AND lengua = ? AND \(condicion)
            ORDER BY vigente_desde DESC, id DESC
            LIMIT 1
            """,
            [.texto(claveEs), .texto(lengua.rawValue)] + valores
        ) { fila in texto(fila, 0) }
        return formas?.first
    }

    /// Significados en español de una palabra de `lengua` vigentes en `fecha`
    /// (o los actuales si `fecha` es nil), ordenados alfabéticamente.
    public func significados(forma: String, lengua: Lengua, en fecha: Date?) -> [String] {
        let (condicion, valores) = vigencia(fecha)
        let filas = try? consultar(
            "SELECT DISTINCT es FROM lexico WHERE forma = ? AND lengua = ? AND \(condicion) ORDER BY es",
            [.texto(forma), .texto(lengua.rawValue)] + valores
        ) { fila in texto(fila, 0) }
        return filas ?? []
    }

    /// Categoría vigente de `forma` en `lengua`. Para `.es` busca por la clave española.
    public func categoria(forma: String, lengua: Lengua) -> String? {
        let (sql, valores): (String, [Valor]) = lengua == .es
            ? ("es_clave = ?", [.texto(BaseDatos.clave(forma))])
            : ("forma = ? AND lengua = ?", [.texto(forma), .texto(lengua.rawValue)])
        let filas = try? consultar(
            """
            SELECT categoria FROM lexico
            WHERE \(sql) AND vigente_hasta IS NULL AND categoria IS NOT NULL
            ORDER BY vigente_desde DESC, id DESC
            LIMIT 1
            """,
            valores
        ) { fila in texto(fila, 0) }
        return filas?.first
    }

    /// Indica si `forma` es hoy una palabra válida de `lengua`.
    public func existeForma(_ forma: String, lengua: Lengua) -> Bool {
        let filas = try? consultar(
            "SELECT 1 FROM lexico WHERE forma = ? AND lengua = ? AND vigente_hasta IS NULL LIMIT 1",
            [.texto(forma), .texto(lengua.rawValue)]
        ) { _ in true }
        return filas?.isEmpty == false
    }

    public func regla(_ clave: String, lengua: Lengua) -> String? {
        let valores = try? consultar(
            """
            SELECT valor FROM regla
            WHERE lengua = ? AND clave = ? AND vigente_hasta IS NULL
            ORDER BY vigente_desde DESC, id DESC
            LIMIT 1
            """,
            [.texto(lengua.rawValue), .texto(clave)]
        ) { fila in texto(fila, 0) }
        return valores?.first
    }

    /// Palabras españolas conocidas: las de las claves vigentes del léxico
    /// (separadas por espacios) más las formas de `vocab_es`, todas normalizadas.
    /// Las terminaciones ("-amos") y raíces ("vendr-") de `vocab_es` llevan guion y no
    /// son palabras: no se incluyen, para que el corrector no las tome por válidas.
    public func vocabularioEspanol() -> Set<String> {
        let filas = try? consultar(
            """
            SELECT es_clave FROM lexico WHERE vigente_hasta IS NULL
            UNION
            SELECT forma FROM vocab_es WHERE instr(forma, '-') = 0
            """,
            []
        ) { fila in texto(fila, 0) }

        var palabras = Set<String>()
        for fila in filas ?? [] {
            for palabra in fila.split(separator: " ") {
                palabras.insert(BaseDatos.clave(String(palabra)))
            }
        }
        palabras.remove("")
        return palabras
    }

    /// Filas de `vocab_es` cuya forma, sin tildes ni mayúsculas, es `forma`.
    /// La comparación se hace con `BaseDatos.clave` en Swift porque la tabla guarda la
    /// forma tal como está en el archivo (con tildes) y SQLite no sabe quitarlas.
    /// Se devuelven en el orden del archivo.
    public func entradasEspanol(forma: String) -> [EntradaVocab] {
        let buscada = BaseDatos.clave(forma)
        let filas = try? consultar(
            "SELECT forma, lema, categoria, rasgos FROM vocab_es ORDER BY id",
            []
        ) { fila in
            EntradaVocab(
                fila: texto(fila, 0), lema: textoOpcional(fila, 1),
                categoria: textoOpcional(fila, 2), rasgos: textoOpcional(fila, 3)
            )
        }
        return (filas ?? []).filter { $0.forma == buscada }
    }

    // MARK: - Lectura de señales

    public struct Senal: Equatable {
        public var id: Int64
        public var dia: Int
        public var voz: String
        public var transcripcion: String
        public var salida: String?

        public init(id: Int64, dia: Int, voz: String, transcripcion: String, salida: String?) {
            self.id = id
            self.dia = dia
            self.voz = voz
            self.transcripcion = transcripcion
            self.salida = salida
        }
    }

    /// Señales cuya transcripción contiene la palabra `forma`, ordenadas por día.
    public func senales(conPalabra forma: String) -> [Senal] {
        let filas = try? consultar(
            """
            SELECT DISTINCT s.id, s.dia, s.voz, s.transcripcion, s.salida
            FROM senal s JOIN senal_palabra p ON p.senal_id = s.id
            WHERE p.forma = ?
            ORDER BY s.dia, s.id
            """,
            [.texto(forma)]
        ) { fila in
            Senal(
                id: entero(fila, 0), dia: Int(entero(fila, 1)), voz: texto(fila, 2),
                transcripcion: texto(fila, 3), salida: textoOpcional(fila, 4)
            )
        }
        return filas ?? []
    }

    /// Formas con las que `forma` puede aparecer en una señal de `lengua`, armadas con
    /// las reglas vigentes: la forma, la forma con cada sufijo (plural, pasado, futuro)
    /// y todas ellas con el prefijo de negación. Solo se usan las reglas que existen
    /// para esa lengua. Una variante que ya es una palabra propia del léxico pertenece
    /// a esa palabra y se descarta.
    func variantes(de forma: String, lengua: Lengua) -> [String] {
        func valor(_ clave: String) -> String? {
            guard let v = regla(clave, lengua: lengua), !v.isEmpty else { return nil }
            return v
        }
        var base = [forma]
        for clave in ["sufijo_plural", "sufijo_pasado", "sufijo_futuro"] {
            if let sufijo = valor(clave) { base.append(forma + sufijo) }
        }
        var todas = base
        if let prefijo = valor("prefijo_negacion") {
            todas += base.map { prefijo + $0 }
        }

        var resultado: [String] = []
        for variante in todas where !resultado.contains(variante) {
            if variante != forma && existeForma(variante, lengua: lengua) { continue }
            resultado.append(variante)
        }
        return resultado
    }

    /// Señales de `lengua` que contienen exactamente `forma` o alguna de sus
    /// variantes (ver `variantes(de:lengua:)`), ordenadas por día.
    public func senales(conForma forma: String, lengua: Lengua) -> [Senal] {
        guard !forma.isEmpty, lengua != .es else { return [] }
        let variantes = variantes(de: forma, lengua: lengua)
        let marcadores = Array(repeating: "?", count: variantes.count).joined(separator: ", ")
        let filas = try? consultar(
            """
            SELECT DISTINCT s.id, s.dia, s.voz, s.transcripcion, s.salida
            FROM senal s JOIN senal_palabra p ON p.senal_id = s.id
            WHERE s.voz = ? AND p.forma IN (\(marcadores))
            ORDER BY s.dia, s.id
            """,
            [.texto(lengua.rawValue)] + variantes.map(Valor.texto)
        ) { fila in
            Senal(
                id: entero(fila, 0), dia: Int(entero(fila, 1)), voz: texto(fila, 2),
                transcripcion: texto(fila, 3), salida: textoOpcional(fila, 4)
            )
        }
        return filas ?? []
    }

    // MARK: - Registro de preguntas

    /// Guarda una pregunta traducida (o rechazada) en el historial.
    /// - Returns: el id asignado.
    @discardableResult
    public func registrar(_ r: RegistroPregunta) throws -> Int64 {
        let json: String
        do {
            json = String(decoding: try JSONEncoder().encode(r.correcciones), as: UTF8.self)
        } catch {
            throw ErrorBD.sql("no se pudieron codificar las correcciones: \(error)")
        }
        try ejecutar(
            """
            INSERT INTO pregunta
              (fecha, original, normalizada, correcciones_json, kethari, ozh,
               valida_k, valida_o, motivo, traza)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .real(r.fecha.timeIntervalSince1970), .texto(r.original), .textoOpcional(r.normalizada),
                .texto(json), .textoOpcional(r.kethari), .textoOpcional(r.ozh),
                .entero(r.validaK ? 1 : 0), .entero(r.validaO ? 1 : 0),
                .textoOpcional(r.motivo), .textoOpcional(r.traza),
            ]
        )
        return sqlite3_last_insert_rowid(db)
    }

    /// Preguntas registradas desde `desde` (incluida), o todas si es nil, por fecha e id.
    public func preguntas(desde: Date?) -> [RegistroPregunta] {
        let filtro = desde.map { ("WHERE fecha >= ?", [Valor.real($0.timeIntervalSince1970)]) } ?? ("", [])
        let filas = try? consultar(
            """
            SELECT id, fecha, original, normalizada, correcciones_json, kethari, ozh,
                   valida_k, valida_o, motivo, traza
            FROM pregunta \(filtro.0)
            ORDER BY fecha, id
            """,
            filtro.1
        ) { fila -> RegistroPregunta in
            let correcciones = (try? JSONDecoder().decode(
                [Correccion].self, from: Data(texto(fila, 4).utf8)
            )) ?? []
            return RegistroPregunta(
                id: entero(fila, 0),
                fecha: Date(timeIntervalSince1970: real(fila, 1)),
                original: texto(fila, 2),
                normalizada: textoOpcional(fila, 3),
                correcciones: correcciones,
                kethari: textoOpcional(fila, 5),
                ozh: textoOpcional(fila, 6),
                validaK: entero(fila, 7) != 0,
                validaO: entero(fila, 8) != 0,
                motivo: textoOpcional(fila, 9),
                traza: textoOpcional(fila, 10)
            )
        }
        return filas ?? []
    }

    // MARK: - Historial de una palabra

    public struct FilaLexico: Equatable {
        public var es: String
        public var lengua: Lengua
        public var forma: String
        public var categoria: String?
        public var vigenteDesde: Date
        public var vigenteHasta: Date?
        /// Archivo de la carga que trajo la fila (`carga.archivo`).
        public var archivo: String?

        public init(
            es: String, lengua: Lengua, forma: String, categoria: String?,
            vigenteDesde: Date, vigenteHasta: Date?, archivo: String?
        ) {
            self.es = es
            self.lengua = lengua
            self.forma = forma
            self.categoria = categoria
            self.vigenteDesde = vigenteDesde
            self.vigenteHasta = vigenteHasta
            self.archivo = archivo
        }
    }

    /// Todas las filas del léxico (vigentes y cerradas) en las que `termino` es la
    /// palabra española o la forma alienígena, ordenadas por lengua y fecha.
    public func historialPalabra(_ termino: String) -> [FilaLexico] {
        let filas = try? consultar(
            """
            SELECT l.es, l.lengua, l.forma, l.categoria, l.vigente_desde, l.vigente_hasta, c.archivo
            FROM lexico l LEFT JOIN carga c ON c.id = l.carga_id
            WHERE l.es_clave = ? OR l.forma = ?
            ORDER BY l.lengua, l.vigente_desde, l.id
            """,
            [.texto(BaseDatos.clave(termino)), .texto(termino)]
        ) { fila -> FilaLexico? in
            guard let lengua = Lengua(rawValue: texto(fila, 1)) else { return nil }
            return FilaLexico(
                es: texto(fila, 0),
                lengua: lengua,
                forma: texto(fila, 2),
                categoria: textoOpcional(fila, 3),
                vigenteDesde: Date(timeIntervalSince1970: real(fila, 4)),
                vigenteHasta: realOpcional(fila, 5).map(Date.init(timeIntervalSince1970:)),
                archivo: textoOpcional(fila, 6)
            )
        }
        return (filas ?? []).compactMap { $0 }
    }

    // MARK: - Utilidades para tests

    /// Filas del léxico (vigentes o no) de una lengua.
    func contarLexico(lengua: Lengua) throws -> Int {
        try consultar("SELECT COUNT(*) FROM lexico WHERE lengua = ?", [.texto(lengua.rawValue)]) { fila in
            Int(entero(fila, 0))
        }.first ?? 0
    }

    struct RegistroCarga: Equatable {
        var tipo: String
        var filas: Int
        var errores: String?
    }

    /// Versión del manual de cada carga, en orden de inserción.
    func versionesCarga() throws -> [String?] {
        try consultar("SELECT version_manual FROM carga ORDER BY id", []) { fila in textoOpcional(fila, 0) }
    }

    /// Todas las señales ordenadas por día e id.
    func todasLasSenales() throws -> [Senal] {
        try consultar("SELECT id, dia, voz, transcripcion, salida FROM senal ORDER BY dia, id", []) { fila in
            Senal(
                id: entero(fila, 0), dia: Int(entero(fila, 1)), voz: texto(fila, 2),
                transcripcion: texto(fila, 3), salida: textoOpcional(fila, 4)
            )
        }
    }

    /// Filas de la tabla `carga` en orden de inserción.
    func registrosCarga() throws -> [RegistroCarga] {
        try consultar("SELECT tipo, filas, errores FROM carga ORDER BY id", []) { fila in
            RegistroCarga(tipo: texto(fila, 0), filas: Int(entero(fila, 1)), errores: textoOpcional(fila, 2))
        }
    }

    /// Número de filas de una tabla del esquema.
    func contarFilas(_ tabla: String) throws -> Int {
        precondition(tabla.allSatisfy { $0.isLetter || $0 == "_" }, "nombre de tabla no válido")
        return try consultar("SELECT COUNT(*) FROM \(tabla)", []) { fila in Int(entero(fila, 0)) }.first ?? 0
    }

    /// Nombres de las tablas creadas por el esquema.
    func tablas() throws -> Set<String> {
        Set(try consultar(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            []
        ) { fila in texto(fila, 0) })
    }

    // MARK: - SQLite de bajo nivel

    private enum Valor {
        case texto(String)
        case real(Double)
        case entero(Int64)
        case nulo

        static func textoOpcional(_ s: String?) -> Valor { s.map(Valor.texto) ?? .nulo }
        static func enteroOpcional(_ n: Int64?) -> Valor { n.map(Valor.entero) ?? .nulo }
    }

    private func ahora() -> Double {
        reloj().timeIntervalSince1970
    }

    private func errorActual() -> ErrorBD {
        .sql(String(cString: sqlite3_errmsg(db)))
    }

    /// Ejecuta uno o varios enunciados SQL sin parámetros.
    private func ejecutarScript(_ sql: String) throws {
        var mensaje: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &mensaje)
        guard rc == SQLITE_OK else {
            let texto = mensaje.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(mensaje)
            throw ErrorBD.sql(texto)
        }
    }

    private func preparar(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_finalize(stmt)
            throw errorActual()
        }
        return stmt
    }

    private func enlazar(_ stmt: OpaquePointer, _ valores: [Valor]) throws {
        for (i, valor) in valores.enumerated() {
            let indice = Int32(i + 1)
            let rc: Int32
            switch valor {
            case .texto(let s): rc = sqlite3_bind_text(stmt, indice, s, -1, SQLITE_TRANSIENT)
            case .real(let d): rc = sqlite3_bind_double(stmt, indice, d)
            case .entero(let n): rc = sqlite3_bind_int64(stmt, indice, n)
            case .nulo: rc = sqlite3_bind_null(stmt, indice)
            }
            guard rc == SQLITE_OK else { throw errorActual() }
        }
    }

    /// Ejecuta un enunciado que no devuelve filas (INSERT, UPDATE...).
    private func ejecutar(_ sql: String, _ valores: [Valor]) throws {
        let stmt = try preparar(sql)
        defer { sqlite3_finalize(stmt) }
        try enlazar(stmt, valores)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw errorActual() }
    }

    /// Ejecuta una consulta y transforma cada fila con `fila`.
    private func consultar<T>(
        _ sql: String, _ valores: [Valor], fila: (OpaquePointer) throws -> T
    ) throws -> [T] {
        let stmt = try preparar(sql)
        defer { sqlite3_finalize(stmt) }
        try enlazar(stmt, valores)
        var resultado: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw errorActual() }
            resultado.append(try fila(stmt))
        }
        return resultado
    }
}

// MARK: - Lectura de columnas

private func texto(_ stmt: OpaquePointer, _ columna: Int32) -> String {
    textoOpcional(stmt, columna) ?? ""
}

private func textoOpcional(_ stmt: OpaquePointer, _ columna: Int32) -> String? {
    guard let c = sqlite3_column_text(stmt, columna) else { return nil }
    return String(cString: c)
}

private func entero(_ stmt: OpaquePointer, _ columna: Int32) -> Int64 {
    sqlite3_column_int64(stmt, columna)
}

private func real(_ stmt: OpaquePointer, _ columna: Int32) -> Double {
    sqlite3_column_double(stmt, columna)
}

private func realOpcional(_ stmt: OpaquePointer, _ columna: Int32) -> Double? {
    sqlite3_column_type(stmt, columna) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, columna)
}
