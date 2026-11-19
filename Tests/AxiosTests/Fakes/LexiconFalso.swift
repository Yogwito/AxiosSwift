import Foundation
@testable import AxiosCore

/// Lexicon en memoria para probar las fases sin base de datos.
/// Ignora la fecha: siempre devuelve la única traducción cargada.
struct LexiconFalso: Lexicon {
    var traducciones: [Lengua: [String: String]]
    var reglas: [Lengua: [String: String]]
    var vocabulario: Set<String>

    init(
        traducciones: [Lengua: [String: String]] = [:],
        reglas: [Lengua: [String: String]] = [:],
        vocabulario: Set<String> = []
    ) {
        self.traducciones = traducciones
        self.reglas = reglas
        self.vocabulario = vocabulario
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
