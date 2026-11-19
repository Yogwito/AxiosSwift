// Contratos compartidos (Tarea 0)

import Foundation

// MARK: - Léxico

public enum TipoToken: Equatable {
    case palabra
    case numero(Int)
    case interrogacion
    case fin
}

public struct Token: Equatable {
    public var tipo: TipoToken
    public var texto: String
    public var linea: Int
    public var columna: Int

    public init(tipo: TipoToken, texto: String, linea: Int, columna: Int) {
        self.tipo = tipo
        self.texto = texto
        self.linea = linea
        self.columna = columna
    }
}

public struct Correccion: Equatable, Codable {
    public var original: String
    public var corregida: String
    public var distancia: Int

    public init(original: String, corregida: String, distancia: Int) {
        self.original = original
        self.corregida = corregida
        self.distancia = distancia
    }
}

// MARK: - Morfología

public enum Tiempo: String, Codable {
    case pasado
    case presente
    case futuro
}

public struct RasgosVerbo: Equatable {
    public var raiz: String
    public var persona: Int
    public var plural: Bool
    public var tiempo: Tiempo

    public init(raiz: String, persona: Int, plural: Bool, tiempo: Tiempo) {
        self.raiz = raiz
        self.persona = persona
        self.plural = plural
        self.tiempo = tiempo
    }
}

// MARK: - Lenguas y léxico

public enum Lengua: String, CaseIterable, Codable {
    case es
    case kethari
    case ozh
}

/// Fuente de traducciones y reglas. Las palabras de las lenguas destino
/// viven en los datos (BD o fakes de prueba), nunca en el código fuente.
public protocol Lexicon {
    /// Traducción de una palabra en español a `lengua`, vigente en `fecha`
    /// (o la más reciente si `fecha` es nil).
    func traduccion(es: String, lengua: Lengua, en fecha: Date?) -> String?
    /// Valor de una regla gramatical (sufijo, partícula, orden...) para `lengua`.
    func regla(_ clave: String, lengua: Lengua) -> String?
    /// Todas las palabras en español conocidas, para la corrección ortográfica.
    func vocabularioEspanol() -> Set<String>
}

// MARK: - Traza

public struct Traza {
    public struct Fase: Equatable {
        public var nombre: String
        public var salida: String

        public init(nombre: String, salida: String) {
            self.nombre = nombre
            self.salida = salida
        }
    }

    public var fases: [Fase]

    public init() {
        self.fases = []
    }

    public mutating func agregar(fase: String, salida: String) {
        fases.append(Fase(nombre: fase, salida: salida))
    }

    /// Una fase por línea con el formato "[nombre] salida", para guardar en BD.
    public func texto() -> String {
        fases.map { "[\($0.nombre)] \($0.salida)" }.joined(separator: "\n")
    }
}

// MARK: - Historial

public struct RegistroPregunta: Equatable {
    public var id: Int64?
    public var fecha: Date
    public var original: String
    public var normalizada: String?
    public var correcciones: [Correccion]
    public var kethari: String?
    public var ozh: String?
    public var validaK: Bool
    public var validaO: Bool
    public var motivo: String?
    public var traza: String?

    public init(
        id: Int64? = nil,
        fecha: Date,
        original: String,
        normalizada: String? = nil,
        correcciones: [Correccion] = [],
        kethari: String? = nil,
        ozh: String? = nil,
        validaK: Bool = false,
        validaO: Bool = false,
        motivo: String? = nil,
        traza: String? = nil
    ) {
        self.id = id
        self.fecha = fecha
        self.original = original
        self.normalizada = normalizada
        self.correcciones = correcciones
        self.kethari = kethari
        self.ozh = ozh
        self.validaK = validaK
        self.validaO = validaO
        self.motivo = motivo
        self.traza = traza
    }
}
