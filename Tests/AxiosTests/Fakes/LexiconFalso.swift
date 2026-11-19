import Foundation
@testable import AxiosCore

/// Lexicon en memoria para probar las fases sin base de datos.
/// Ignora la fecha: siempre devuelve la única traducción cargada.
struct LexiconFalso: Lexicon {
    var traducciones: [Lengua: [String: String]]
    var reglas: [Lengua: [String: String]]
    var vocabulario: Set<String>
    /// Categoría de cada forma, por lengua.
    var categorias: [Lengua: [String: String]]

    init(
        traducciones: [Lengua: [String: String]] = [:],
        reglas: [Lengua: [String: String]] = [:],
        vocabulario: Set<String> = [],
        categorias: [Lengua: [String: String]] = [:]
    ) {
        self.traducciones = traducciones
        self.reglas = reglas
        self.vocabulario = vocabulario
        self.categorias = categorias
    }

    func categoria(forma: String, lengua: Lengua) -> String? {
        categorias[lengua]?[forma]
    }

    func traduccion(es: String, lengua: Lengua, en fecha: Date?) -> String? {
        traducciones[lengua]?[es]
    }

    func regla(_ clave: String, lengua: Lengua) -> String? {
        reglas[lengua]?[clave]
    }

    func vocabularioEspanol() -> Set<String> {
        vocabulario
    }
}
