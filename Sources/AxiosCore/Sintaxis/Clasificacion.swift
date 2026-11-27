// Terminales de la BNF (docs/memoria.md, sección "BNF"). La gramática no nombra
// palabras: pide categorías (PRON, ART, SUST, VERBO...). Aquí se decide a qué
// categorías pertenece cada token, consultando vocab_es y la morfología.

import Foundation

/// Error del analizador sintáctico: qué pasó y en qué token (línea y columna).
public struct ErrorSintactico: Error, Equatable {
    public var motivo: String
    public var linea: Int
    public var columna: Int

    public init(motivo: String, linea: Int, columna: Int) {
        self.motivo = motivo
        self.linea = linea
        self.columna = columna
    }

    init(_ motivo: String, en token: Token) {
        self.init(motivo: motivo, linea: token.linea, columna: token.columna)
    }

    /// "columna 9: palabra desconocida 'xyz'".
    public func texto() -> String {
        "columna \(columna): \(motivo)"
    }
}

/// Las categorías de un token. Una palabra puede tener varias: sin tildes "el" es
/// artículo y pronombre; la gramática decide cuál usar según el contexto (R12).
struct ClaseToken {
    var interrogativo: EntradaVocab?   // INTERROG
    var pronombre: EntradaVocab?       // PRON
    var articulo: EntradaVocab?        // ART
    var posesivo: EntradaVocab?        // POS
    var negacion = false               // NEG
    var preposicion: String?           // PREP (su clave: "a")
    var nominales: [AnalisisNominal] = []  // SUST
    var verbos: [AnalisisVerbal] = []      // VERBO
    var infinitivo: String?                // INF

    /// Al menos una categoría: la palabra es conocida.
    var esConocida: Bool {
        interrogativo != nil || pronombre != nil || articulo != nil || posesivo != nil
            || negacion || preposicion != nil || !nominales.isEmpty || !verbos.isEmpty || infinitivo != nil
    }
}

/// Nombres de categorías y rasgos de vocab_es que usa la sintaxis (formato de los
/// datos, como los nombres de las columnas; no son palabras del español).
enum FormatoSintaxis {
    static let interrogativo = "interrogativo"
    static let pronombre = "pronombre"
    static let articulo = "articulo"
    static let posesivo = "posesivo"
    static let negacion = "negacion"
    static let preposicion = "preposicion"
    static let perifrasis = "perifrasis"
    static let funcion = "f"
    static let tiempo = "t"
    static let resultado = "resultado"
    static let transitividad = "transitividad"
    static let rasgoTransitividad = "tr"
}

/// Valores del rasgo tr de vocab_es (regla R4).
enum Transitividad: String {
    case transitivo, intransitivo, copulativo
}

extension EntradaVocab {
    /// Persona del rasgo p (1, 2, 3).
    var persona: Int? { Int(rasgos["p"] ?? "") }
    /// Persona con la que concuerda el verbo: pv si existe ("ustedes": 3), si no p.
    var personaConcordancia: Int? { Int(rasgos["pv"] ?? "") ?? persona }
    /// Número del rasgo n, o nil si la fila no lo dice.
    var plural: Bool? { rasgos["n"].map { $0 == "pl" } }
    /// Primer lema candidato, o la forma si no hay lema.
    var lemaPreferido: String { lemas.first ?? forma }
}

/// Clasifica tokens con los datos. No guarda estado: se puede probar con `LexiconFalso`.
struct Clasificador {
    let lexicon: Lexicon
    let morfologia: Morfologia

    init(lexicon: Lexicon) {
        self.lexicon = lexicon
        self.morfologia = Morfologia(lexicon: lexicon)
    }

    /// Categorías de `token`. Los tokens que no son `.palabra` no tienen ninguna
    /// (SIGNO, NUM y FIN se reconocen por su tipo).
    func clasificar(_ token: Token) -> ClaseToken {
        guard token.tipo == .palabra else { return ClaseToken() }
        let entradas = lexicon.entradasEspanol(forma: token.texto)
        func primera(_ categoria: String) -> EntradaVocab? {
            entradas.first { $0.categoria == categoria }
        }
        var clase = ClaseToken()
        clase.interrogativo = primera(FormatoSintaxis.interrogativo)
        clase.pronombre = primera(FormatoSintaxis.pronombre)
        clase.articulo = primera(FormatoSintaxis.articulo)
        clase.posesivo = primera(FormatoSintaxis.posesivo)
        clase.negacion = primera(FormatoSintaxis.negacion) != nil
        clase.preposicion = primera(FormatoSintaxis.preposicion)?.forma
        clase.nominales = morfologia.analizarSustantivo(token.texto)
        clase.verbos = morfologia.analizarVerbo(token.texto)
        clase.infinitivo = morfologia.infinitivo(token.texto)
        return clase
    }

    /// Filas de perífrasis cuyo verbo es `lema` ("ir" → ir|a|perifrasis|...).
    func perifrasis(de lema: String) -> [EntradaVocab] {
        lexicon.entradasEspanol(forma: lema).filter { $0.categoria == FormatoSintaxis.perifrasis }
    }

    /// Transitividad de un verbo según su fila de vocab_es, o nil si no la declara.
    func transitividad(de lema: String) -> Transitividad? {
        lexicon.entradasEspanol(forma: lema)
            .first { $0.categoria == FormatoSintaxis.transitividad }?
            .rasgos[FormatoSintaxis.rasgoTransitividad]
            .flatMap(Transitividad.init(rawValue:))
    }

    /// El pronombre personal de un lema ("nosotros"), para los poseedores (R11).
    func pronombre(lema: String) -> Pronombre? {
        guard let fila = lexicon.entradasEspanol(forma: lema).first(where: { $0.categoria == FormatoSintaxis.pronombre }),
              let persona = fila.persona, let plural = fila.plural
        else { return nil }
        return Pronombre(lema: fila.lemaPreferido, persona: persona, plural: plural)
    }
}
