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
        /// Raíz irregular de `vocab_es` + terminación: "vendr-án", "vien-en".
        case raizIrregular = "raiz irregular"
        /// Forma completa de `vocab_es`, que no se parte: "van", "fue", "soy".
        case supletiva
    }

    /// `raiz` es el infinitivo, como clave del léxico ("enviar").
    public var rasgos: RasgosVerbo
    public var procedencia: Procedencia
    /// Terminación que se reconoció ("-aron"), como clave sin tildes; nil en las supletivas.
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

/// Una lectura de una forma como sustantivo: su lema en singular y su número.
public struct AnalisisNominal: Equatable {
    /// Singular, como clave del léxico ("nave" para "naves").
    public var lema: String
    public var plural: Bool

    public init(lema: String, plural: Bool) {
        self.lema = lema
        self.plural = plural
    }
}

/// Todo lo que la morfología sabe de un token: sus lecturas como verbo conjugado,
/// como infinitivo y como sustantivo (puede tener varias o ninguna).
public struct AnalisisToken: Equatable {
    public var token: Token
    public var verbos: [AnalisisVerbal]
    public var infinitivo: String?
    public var nominales: [AnalisisNominal]

    public init(token: Token, verbos: [AnalisisVerbal], infinitivo: String?, nominales: [AnalisisNominal]) {
        self.token = token
        self.verbos = verbos
        self.infinitivo = infinitivo
        self.nominales = nominales
    }

    /// Más de una lectura verbal: "enviamos" (presente o pasado), "fue" (ser o ir).
    public var esAmbiguo: Bool { verbos.count > 1 }

    /// "enviar 1pl presente / enviar 1pl pasado", "inf llegar", "nave+pl" o "—".
    func texto() -> String {
        var partes = verbos.map { $0.texto() }
        if let infinitivo { partes.append("inf \(infinitivo)") }
        partes += nominales.map { $0.plural ? "\($0.lema)+pl" : $0.lema }
        return partes.isEmpty ? "—" : partes.joined(separator: " / ")
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
        static let raizIrregular = "raiz_irregular"
        static let raizExcluida = "raiz_excluida"
        static let terminacionPlural = "terminacion_plural"
        static let infinitivo = "infinitivo"
        static let verbo = "verbo"
        static let sustantivo = "sustantivo"
        static let persona = "p"
        static let numero = "n"
        static let plural = "pl"
        static let tiempo = "t"
        static let base = "base"
        static let clase = "clase"
        static let baseInfinitivo = "infinitivo"
    }

    // MARK: - Verbos

    /// Todas las lecturas de `forma` como verbo conjugado, o [] si no es un verbo
    /// conjugado conocido. No mira tildes ni mayúsculas.
    public func analizarVerbo(_ forma: String) -> [AnalisisVerbal] {
        let clave = BaseDatos.clave(forma)

        // Una forma supletiva se toma entera y no se intenta partir: "fue" → ser, ir.
        let supletivas = lexicon.entradasEspanol(forma: clave).filter { $0.categoria == Formato.verbo }
        if !supletivas.isEmpty {
            return sinRepetir(supletivas.flatMap { entrada in
                entrada.lemas.filter(esVerbo).compactMap { lema in
                    rasgos(lema, entrada).map {
                        AnalisisVerbal(rasgos: $0, procedencia: .supletiva, terminacion: nil)
                    }
                }
            })
        }

        let letras = Array(clave)
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

    /// El infinitivo como clave si `forma` es un infinitivo conocido ("llegar", "ir").
    /// Lo usa el analizador sintáctico para "ir a + infinitivo".
    public func infinitivo(_ forma: String) -> String? {
        let clave = BaseDatos.clave(forma)
        return esVerbo(clave) ? clave : nil
    }

    // MARK: - Sustantivos

    /// Lecturas de `forma` como sustantivo: el singular si está en el léxico ("paz"),
    /// o el plural quitando la terminación más larga que deje un sustantivo conocido
    /// ("naves" → nave, "luces" → luz).
    public func analizarSustantivo(_ forma: String) -> [AnalisisNominal] {
        let clave = BaseDatos.clave(forma)
        if esSustantivo(clave) {
            return [AnalisisNominal(lema: clave, plural: false)]
        }
        let letras = Array(clave)
        guard letras.count > 1 else { return [] }
        for corte in 1..<letras.count {
            let resto = String(letras[..<corte])
            let terminacion = "-" + String(letras[corte...])
            let lecturas = lexicon.entradasEspanol(forma: terminacion)
                .filter { $0.categoria == Formato.terminacionPlural }
                .map { resto + ($0.lemas.first ?? "") }  // el lema es lo que se repone: luc-es → luz
                .filter(esSustantivo)
                .map { AnalisisNominal(lema: $0, plural: true) }
            if !lecturas.isEmpty {
                return sinRepetir(lecturas)
            }
        }
        return []
    }

    private func esSustantivo(_ lema: String) -> Bool {
        lexicon.categoria(forma: lema, lengua: .es) == Formato.sustantivo
    }

    // MARK: - Etiquetado de tokens

    /// Analiza cada token `.palabra` por separado: es lo que recibe el analizador
    /// sintáctico y lo que se muestra en la traza. Los demás tokens (números, signos,
    /// fin) no se analizan. "ir a + infinitivo" no se junta aquí: cada palabra lleva su
    /// propia etiqueta y el analizador sintáctico reconoce la construcción.
    public func etiquetar(_ tokens: [Token]) -> [AnalisisToken] {
        tokens.compactMap { token in
            guard token.tipo == .palabra else { return nil }
            return AnalisisToken(
                token: token,
                verbos: analizarVerbo(token.texto),
                infinitivo: infinitivo(token.texto),
                nominales: analizarSustantivo(token.texto)
            )
        }
    }

    /// Una línea para la traza: "van: ir 3pl presente | a: — | llegar: inf llegar".
    public static func texto(_ etiquetas: [AnalisisToken]) -> String {
        etiquetas.map { "\($0.token.texto): \($0.texto())" }.joined(separator: " | ")
    }

    // MARK: - Para el corrector

    /// Indica si `forma` es una palabra española válida: está en el léxico o en
    /// `vocab_es` como palabra completa, o la morfología la reconoce como verbo
    /// conjugado, infinitivo o plural. El corrector ortográfico debe preguntar aquí
    /// antes de corregir: las formas regulares ("llegan", "naves") no están en
    /// `vocabularioEspanol()` porque se analizan, no se listan.
    public func reconoce(_ forma: String) -> Bool {
        let clave = BaseDatos.clave(forma)
        guard !clave.isEmpty, !clave.contains("-") else { return false }  // un morfema no es una palabra
        return lexicon.categoria(forma: clave, lengua: .es) != nil
            || !lexicon.entradasEspanol(forma: clave).isEmpty
            || !analizarVerbo(clave).isEmpty
            || !analizarSustantivo(clave).isEmpty
    }

    // MARK: - Utilidades

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
        guard let tiempoTerminacion = tiempo(de: entrada) else { return [] }
        let clases = entrada.lemas  // ar, er, ir: verbos a los que se aplica
        let pegadaAlInfinitivo = entrada.rasgos[Formato.base] == Formato.baseInfinitivo

        // Filas de vocab_es para esta raíz ("vendr-", "ven-") en el mismo tiempo.
        let filasRaiz = lexicon.entradasEspanol(forma: raiz + "-").filter {
            tiempo(de: $0) == tiempoTerminacion
        }
        func lemas(_ categoria: String) -> [String] {
            filasRaiz.filter { $0.categoria == categoria }.flatMap(\.lemas)
        }

        // 1. Raíz irregular: "vendr-" + "-an" → venir. Si la terminación va pegada a la
        //    raíz, el verbo tiene que ser de una de sus clases ("vien-en": venir es -ir),
        //    salvo que la raíz diga con qué clase se conjuga ("estuv-" va como -er).
        let irregulares = filasRaiz.filter { $0.categoria == Formato.raizIrregular }.flatMap { fila in
            fila.lemas.filter { lema in
                let clase = fila.rasgos[Formato.clase]
                let encaja = clase.map { clases.contains($0) } ?? clases.contains { lema.hasSuffix($0) }
                return esVerbo(lema) && (pegadaAlInfinitivo || encaja)
            }
        }

        // 2. Raíz regular. En el futuro la terminación va pegada al infinitivo
        //    ("llegar-an"); en los demás tiempos, a la raíz ("lleg-an" → lleg + ar).
        //    Se descartan los verbos que en este tiempo no usan su raíz regular
        //    ("ven-imos" no es pasado: el pasado de venir es "vin-imos").
        let excluidos = Set(lemas(Formato.raizExcluida))
        let regulares = (pegadaAlInfinitivo
            ? (clases.contains { raiz.hasSuffix($0) } ? [raiz] : [])
            : clases.map { raiz + $0 }
        ).filter { esVerbo($0) && !excluidos.contains($0) }

        let lecturas = irregulares.map { ($0, AnalisisVerbal.Procedencia.raizIrregular) }
            + regulares.map { ($0, AnalisisVerbal.Procedencia.regular) }
        return lecturas.compactMap { lema, procedencia in
            rasgos(lema, entrada).map {
                AnalisisVerbal(rasgos: $0, procedencia: procedencia, terminacion: entrada.forma)
            }
        }
    }

    /// Rasgos de `lema` con la persona, el número y el tiempo de `entrada`.
    private func rasgos(_ lema: String, _ entrada: EntradaVocab) -> RasgosVerbo? {
        guard let tiempo = tiempo(de: entrada),
              let persona = Int(entrada.rasgos[Formato.persona] ?? ""),
              let numero = entrada.rasgos[Formato.numero]
        else { return nil }
        return RasgosVerbo(raiz: lema, persona: persona, plural: numero == Formato.plural, tiempo: tiempo)
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
