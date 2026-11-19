PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS carga (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  archivo        TEXT    NOT NULL,
  tipo           TEXT    NOT NULL CHECK (tipo IN ('lexico','reglas','senales','vocab_es')),
  version_manual TEXT,
  cargada_en     REAL    NOT NULL,
  filas          INTEGER NOT NULL DEFAULT 0,
  errores        TEXT
);

CREATE TABLE IF NOT EXISTS lexico (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  es            TEXT NOT NULL,
  es_clave      TEXT NOT NULL,
  lengua        TEXT NOT NULL CHECK (lengua IN ('kethari','ozh')),
  forma         TEXT NOT NULL,
  categoria     TEXT,
  carga_id      INTEGER REFERENCES carga(id),
  vigente_desde REAL NOT NULL,
  vigente_hasta REAL
);
CREATE INDEX IF NOT EXISTS idx_lexico_es    ON lexico(es_clave, lengua);
CREATE INDEX IF NOT EXISTS idx_lexico_forma ON lexico(forma, lengua);

CREATE TABLE IF NOT EXISTS regla (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  lengua        TEXT NOT NULL CHECK (lengua IN ('kethari','ozh')),
  clave         TEXT NOT NULL,
  valor         TEXT NOT NULL,
  carga_id      INTEGER REFERENCES carga(id),
  vigente_desde REAL NOT NULL,
  vigente_hasta REAL
);
CREATE INDEX IF NOT EXISTS idx_regla ON regla(lengua, clave);

CREATE TABLE IF NOT EXISTS senal (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  dia           INTEGER NOT NULL,
  voz           TEXT    NOT NULL,
  transcripcion TEXT    NOT NULL DEFAULT '',
  salida        TEXT,
  carga_id      INTEGER REFERENCES carga(id),
  UNIQUE (dia, voz, transcripcion)
);

CREATE TABLE IF NOT EXISTS senal_palabra (
  senal_id INTEGER NOT NULL REFERENCES senal(id) ON DELETE CASCADE,
  posicion INTEGER NOT NULL,
  forma    TEXT    NOT NULL,
  PRIMARY KEY (senal_id, posicion)
);
CREATE INDEX IF NOT EXISTS idx_senal_palabra ON senal_palabra(forma);

CREATE TABLE IF NOT EXISTS vocab_es (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  forma     TEXT NOT NULL,
  lema      TEXT,
  categoria TEXT,
  rasgos    TEXT,
  UNIQUE (forma, categoria)
);

CREATE TABLE IF NOT EXISTS pregunta (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha             REAL    NOT NULL,
  original          TEXT    NOT NULL,
  normalizada       TEXT,
  correcciones_json TEXT    NOT NULL DEFAULT '[]',
  kethari           TEXT,
  ozh               TEXT,
  valida_k          INTEGER NOT NULL DEFAULT 0,
  valida_o          INTEGER NOT NULL DEFAULT 0,
  motivo            TEXT,
  traza             TEXT
);
CREATE INDEX IF NOT EXISTS idx_pregunta_fecha ON pregunta(fecha);
