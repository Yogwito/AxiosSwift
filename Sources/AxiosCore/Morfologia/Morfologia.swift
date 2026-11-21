// Morfología del español: de una forma conjugada ("enviaron") saca el infinitivo,
// la persona, el número y el tiempo. No hay ninguna terminación ni ningún verbo
// escrito aquí: todo sale de `vocab_es` (data/vocab_es_v0.7.txt) y del léxico. El
// código solo trae el algoritmo:
//   1. probar las terminaciones de la más larga a la más corta;
//   2. reconstruir el infinitivo (raíz + clase del verbo, o la raíz misma en el futuro);
//   3. quedarse solo con los infinitivos que son verbos conocidos.
// Si una forma admite varias lecturas ("enviamos": presente o pasado) se devuelven
// todas, en el orden del archivo de datos, y decide el analizador sintáctico.

import Foundation

/// Una lectura posible de una forma verbal conjugada.
public struct AnalisisVerbal: Equatable {
    public enum Procedencia: String, Equatable {
        /// Raíz regular + terminación: "envi-aron".
        case regular
    }

    /// `raiz` es el infinitivo, como clave del léxico ("enviar").
    public var rasgos: RasgosVerbo
    public var procedencia: Procedencia
    /// Terminación que se reconoció ("-aron"), como clave sin tildes.
    public var terminacion: String?

    public init(rasgos: RasgosVerbo, procedencia: Procedencia, terminacion: String?) {
        self.rasgos = rasgos
        self.procedencia = procedencia
        self.terminacion = terminacion
    }

    /// "enviar 3pl pasado".
    public func texto() -> String {
        "\(rasgos.raiz) \(rasgos.persona)\(rasgos.plural ? "pl" : "sg") \(rasgos.tiempo.rawValue)"
    }
}

/// Analizador morfológico. Solo depende del protocolo `Lexicon`, así se prueba igual
/// con la BD real que con un `LexiconFalso` de palabras inventadas.
public struct Morfologia {
    private let lexicon: Lexicon

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// Nombres del formato de `vocab_es` (como los nombres de las columnas, no son
    /// palabras del español).
    enum Formato {
        static let prefijoTerminacion = "terminacion_"
        static let infinitivo = "infinitivo"
        static let verbo = "verbo"
        static let persona = "p"
        static let numero = "n"
        static let plural = "pl"
        static let tiempo = "t"
        static let base = "base"
        static let baseInfinitivo = "infinitivo"
    }

    // MARK: - Verbos

    /// Todas las lecturas de `forma` como verbo conjugado, o [] si no es un verbo
    /// conjugado conocido. No mira tildes ni mayúsculas.
    public func analizarVerbo(_ forma: String) -> [AnalisisVerbal] {
        let letras = Array(BaseDatos.clave(forma))
        guard letras.count > 1 else { return [] }

        // De la terminación más larga a la más corta; la raíz nunca queda vacía.
        for corte in 1..<letras.count {
            let raiz = String(letras[..<corte])
            let terminacion = "-" + String(letras[corte...])
            let lecturas = terminacionesVerbales(terminacion).flatMap { analizar(raiz: raiz, con: $0) }
            if !lecturas.isEmpty {
                return sinRepetir(lecturas)
            }
        }
        return []
    }

    /// Indica si `lema` es un verbo conocido: está en el léxico como verbo o en
    /// `vocab_es` como infinitivo ("ir", que no tiene traducción propia).
    func esVerbo(_ lema: String) -> Bool {
        lexicon.categoria(forma: lema, lengua: .es) == Formato.verbo
            || lexicon.entradasEspanol(forma: lema).contains { $0.categoria == Formato.infinitivo }
    }

    /// Filas de `vocab_es` que son terminaciones verbales con esa forma ("-an" da la
    /// del presente y la del futuro).
    private func terminacionesVerbales(_ terminacion: String) -> [EntradaVocab] {
        lexicon.entradasEspanol(forma: terminacion).filter {
            ($0.categoria ?? "").hasPrefix(Formato.prefijoTerminacion) && tiempo(de: $0) != nil
        }
    }

    /// Lecturas de `raiz` + la terminación `entrada`.
    private func analizar(raiz: String, con entrada: EntradaVocab) -> [AnalisisVerbal] {
        guard let tiempo = tiempo(de: entrada),
              let persona = Int(entrada.rasgos[Formato.persona] ?? ""),
              let numero = entrada.rasgos[Formato.numero]
        else { return [] }
        let clases = entrada.lemas  // ar, er, ir: verbos a los que se aplica
        let pegadaAlInfinitivo = entrada.rasgos[Formato.base] == Formato.baseInfinitivo

        // En el futuro la terminación va pegada al infinitivo ("llegar-an"); en los
        // demás tiempos, a la raíz ("lleg-an" → lleg + ar).
        let infinitivos = pegadaAlInfinitivo
            ? (clases.contains { raiz.hasSuffix($0) } ? [raiz] : [])
            : clases.map { raiz + $0 }

        return infinitivos.filter(esVerbo).map { infinitivo in
            AnalisisVerbal(
                rasgos: RasgosVerbo(
                    raiz: infinitivo, persona: persona, plural: numero == Formato.plural, tiempo: tiempo
                ),
                procedencia: .regular,
                terminacion: entrada.forma
            )
        }
    }

    private func tiempo(de entrada: EntradaVocab) -> Tiempo? {
        Tiempo(rawValue: entrada.rasgos[Formato.tiempo] ?? "")
    }

    /// Quita lecturas repetidas conservando el orden.
    private func sinRepetir<T: Equatable>(_ lista: [T]) -> [T] {
        var resultado: [T] = []
        for x in lista where !resultado.contains(x) {
            resultado.append(x)
        }
        return resultado
    }
}
