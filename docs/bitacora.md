# Bitácora de decisiones

| Fecha | Problema | Opciones | Decisión | Prueba |
|-------|----------|----------|----------|--------|
| 2026-11-18 | `import SQLite3` solo existe en plataformas Apple; el proyecto debe compilar igual en macOS, Windows y Linux | `import SQLite3` del sistema; paquete SQLite de terceros; SQLite embebido (amalgamation) como target C | SQLite embebido (amalgamation 3.54.1) en vez de `import SQLite3`, para compilar en macOS, Windows y Linux | `EsqueletoTests.testSQLiteEnMemoriaAbre`: abre `":memory:"` con `sqlite3_open` y verifica `SQLITE_OK` |
