import Foundation

/// Resultado de validar una frase en Kethari u Ozh.
public struct ResultadoValidacion: Equatable {
    public var valida: Bool
    public var motivo: String?
    /// Columna (desde 1) donde se detectó el problema, si se puede señalar.
    public var columna: Int?
    /// Descripción del árbol cuando la frase es válida, por ejemplo "[S x] [O y] [V z] [PREG]".
    public var estructura: String?

    public init(valida: Bool, motivo: String?, columna: Int?, estructura: String?) {
        self.valida = valida
        self.motivo = motivo
        self.columna = columna
        self.estructura = estructura
    }

    static func aceptada(_ estructura: String) -> ResultadoValidacion {
        ResultadoValidacion(valida: true, motivo: nil, columna: nil, estructura: estructura)
    }

    static func error(_ motivo: String, columna: Int?) -> ResultadoValidacion {
        ResultadoValidacion(valida: false, motivo: motivo, columna: columna, estructura: nil)
    }
}

/// Error interno de los analizadores sintácticos.
struct ErrorValidacion: Error {
    var motivo: String
    var columna: Int?
}

/// Nombres de categoría usados en el léxico (columna `categoria`).
enum Categoria {
    static let pronombre = "pronombre"
    static let sustantivo = "sustantivo"
    static let verbo = "verbo"
    static let interrogativo = "interrogativo"
}

extension Lengua {
    /// Nombre para mensajes: "Kethari", "Ozh".
    var nombre: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Lee un valor de regla no vacío.
func valorRegla(_ lexicon: Lexicon, _ clave: String, _ lengua: Lengua) -> String? {
    guard let v = lexicon.regla(clave, lengua: lengua), !v.isEmpty else { return nil }
    return v
}

/// Lee una regla cuyo valor es una lista separada por comas (por ejemplo "particulas").
func listaRegla(_ lexicon: Lexicon, _ clave: String, _ lengua: Lengua) -> [String] {
    (valorRegla(lexicon, clave, lengua) ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// Cifras de una lengua y cómo se combinan, sacadas del léxico y las reglas:
/// la cifra d es la traducción de la palabra española "d" (0, 1, 2...) para d < base,
/// y las cifras se unen con `separador_numero`.
struct Cifras {
    let lengua: Lengua
    let base: Int?
    let separador: String?
    let valores: [String: Int]

    /// Máximo de cifras de un número: el valor debe ser menor que base^6.
    static let maximoCifras = 6

    init(lexicon: Lexicon, lengua: Lengua) {
        self.lengua = lengua
        base = valorRegla(lexicon, "base", lengua).flatMap { Int($0) }
        separador = valorRegla(lexicon, "separador_numero", lengua)
        var valores: [String: Int] = [:]
        if let base {
            for d in 0..<min(base, 10) {
                if let forma = lexicon.traduccion(es: String(d), lengua: lengua, en: nil) {
                    valores[forma] = d
                }
            }
        }
        self.valores = valores
    }

    /// La palabra tiene forma de número: una cifra o cifras unidas por el separador.
    func pareceNumero(_ texto: String) -> Bool {
        if valores[texto] != nil { return true }
        guard let separador else { return false }
        return texto.contains(separador)
    }

    /// Valor del número escrito en `token`; error con la columna de la cifra inválida.
    func valor(de token: Token) throws -> Int {
        guard let base else {
            throw ErrorValidacion(motivo: "falta la regla 'base' de \(lengua.nombre)", columna: token.columna)
        }
        let partes = separador.map { token.texto.components(separatedBy: $0) } ?? [token.texto]
        var valor = 0
        var desplazamiento = 0
        for parte in partes {
            guard let cifra = valores[parte] else {
                throw ErrorValidacion(
                    motivo: "cifra '\(parte)' no existe en \(lengua.nombre)",
                    columna: token.columna + desplazamiento
                )
            }
            valor = valor * base + cifra
            desplazamiento += parte.count + (separador?.count ?? 0)
        }
        let limite = Int(pow(Double(base), Double(Cifras.maximoCifras)))
        guard valor < limite else {
            throw ErrorValidacion(
                motivo: "número demasiado grande (\(valor)): debe ser menor que \(limite)",
                columna: token.columna
            )
        }
        return valor
    }
}

/// Cursor sobre los tokens, común a los dos analizadores.
struct Cursor {
    let tokens: [Token]
    var posicion = 0

    var actual: Token { tokens[posicion] }
    var siguiente: Token? { posicion + 1 < tokens.count ? tokens[posicion + 1] : nil }
    var alFinal: Bool { actual.tipo == .fin }

    @discardableResult
    mutating func avanzar() -> Token {
        let t = actual
        if !alFinal { posicion += 1 }
        return t
    }
}

/// Tokeniza y ejecuta el analizador; convierte cualquier error en `ResultadoValidacion`.
func validar(
    _ s: String, analizar: (inout Cursor) throws -> String
) -> ResultadoValidacion {
    switch TokenizadorAlien.tokenizar(s) {
    case .failure(let e):
        return .error(e.motivo, columna: e.columna)
    case .success(let tokens):
        guard tokens.count > 1 else { return .error("frase vacía", columna: nil) }
        var cursor = Cursor(tokens: tokens)
        do {
            return .aceptada(try analizar(&cursor))
        } catch let e as ErrorValidacion {
            return .error(e.motivo, columna: e.columna)
        } catch {
            return .error("\(error)", columna: nil)
        }
    }
}
