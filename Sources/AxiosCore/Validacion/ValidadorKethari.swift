import Foundation

/// Valida una frase en Kethari con un analizador descendente recursivo.
///
///     <oracion> ::= [<interrog>] <sn>* <verbo> [<preg>]
///     <sn>      ::= <pronombre> | [<numero>] [<pronombre>] <nombre>
///     <nombre>  ::= raiz-sustantivo [sufijo_plural]
///     <verbo>   ::= [prefijo_negacion] raiz-verbo [sufijo_pasado | sufijo_futuro]
///     <numero>  ::= <cifra> { separador_numero <cifra> }
///     <preg>    ::= particula_pregunta
///
/// Las palabras, categorías y afijos salen del `Lexicon`; aquí no hay ninguno escrito.
/// No usa código de generación: solo el léxico, las reglas y el tokenizador.
public func validarKethari(_ s: String, lexicon: Lexicon) -> ResultadoValidacion {
    let analizador = AnalizadorKethari(lexicon: lexicon)
    return validar(s) { cursor in try analizador.oracion(&cursor) }
}

private struct AnalizadorKethari {
    let lexicon: Lexicon
    let cifras: Cifras
    let sufijoPlural: String?
    let sufijosTiempo: [String]
    let prefijoNegacion: String?
    let particulaPregunta: String?
    let interrogativosSujeto: [String]

    init(lexicon: Lexicon) {
        self.lexicon = lexicon
        cifras = Cifras(lexicon: lexicon, lengua: .kethari)
        sufijoPlural = valorRegla(lexicon, "sufijo_plural", .kethari)
        sufijosTiempo = ["sufijo_pasado", "sufijo_futuro"].compactMap { valorRegla(lexicon, $0, .kethari) }
        prefijoNegacion = valorRegla(lexicon, "prefijo_negacion", .kethari)
        particulaPregunta = valorRegla(lexicon, "particula_pregunta", .kethari)
        interrogativosSujeto = listaRegla(lexicon, "interrogativo_sujeto", .kethari)
    }

    // MARK: - Clasificación de palabras (análisis de afijos)

    private func categoria(_ forma: String) -> String? {
        lexicon.categoria(forma: forma, lengua: .kethari)
    }

    func esPronombre(_ t: Token) -> Bool { categoria(t.texto) == Categoria.pronombre }
    func esInterrogativo(_ t: Token) -> Bool { categoria(t.texto) == Categoria.interrogativo }
    func esPregunta(_ t: Token) -> Bool { t.tipo == .palabra && t.texto == particulaPregunta }

    /// Nombre: raíz sustantivo, sola o con el sufijo de plural. Devuelve si es plural.
    func analizarNombre(_ texto: String) -> Bool? {
        if categoria(texto) == Categoria.sustantivo { return false }
        if let sufijo = sufijoPlural, texto.hasSuffix(sufijo),
           categoria(String(texto.dropLast(sufijo.count))) == Categoria.sustantivo {
            return true
        }
        return nil
    }

    /// Verbo: [prefijo de negación] raíz verbo [sufijo de pasado o futuro].
    func esVerbo(_ t: Token) -> Bool {
        guard t.tipo == .palabra else { return false }
        if categoria(t.texto) == Categoria.verbo { return true }

        var sinPrefijo = [t.texto]
        if let prefijo = prefijoNegacion, t.texto.hasPrefix(prefijo) {
            sinPrefijo.append(String(t.texto.dropFirst(prefijo.count)))
        }
        for palabra in sinPrefijo {
            if categoria(palabra) == Categoria.verbo { return true }
            for sufijo in sufijosTiempo where palabra.hasSuffix(sufijo) {
                if categoria(String(palabra.dropLast(sufijo.count))) == Categoria.verbo { return true }
            }
        }
        return false
    }

    func esConocida(_ t: Token) -> Bool {
        esPronombre(t) || esInterrogativo(t) || esPregunta(t) || analizarNombre(t.texto) != nil
            || esVerbo(t) || cifras.pareceNumero(t.texto)
    }

    // MARK: - <oracion>

    func oracion(_ c: inout Cursor) throws -> String {
        if let desconocida = c.tokens.first(where: { $0.tipo == .palabra && !esConocida($0) }) {
            throw ErrorValidacion(motivo: "palabra desconocida '\(desconocida.texto)'", columna: desconocida.columna)
        }

        var partes: [String] = []
        let interrogativo = try interrog(&c)
        // Si el interrogativo es sujeto (regla interrogativo_sujeto), todos los SN son objetos.
        let interrogativoEsSujeto = interrogativo.map(interrogativosSujeto.contains) ?? false
        if let interrogativo {
            partes.append(interrogativoEsSujeto ? "[S \(interrogativo)]" : "[INT \(interrogativo)]")
        }

        var sintagmas = 0
        while !c.alFinal && !esVerbo(c.actual) {
            let haySujeto = interrogativoEsSujeto || sintagmas > 0
            let texto = try sn(&c, haySujeto: haySujeto)
            partes.append("[\(haySujeto ? "O" : "S") \(texto)]")
            sintagmas += 1
        }

        guard !c.alFinal else {
            throw ErrorValidacion(motivo: "falta el verbo", columna: c.actual.columna)
        }
        if interrogativo == nil && sintagmas == 0 {
            throw ErrorValidacion(
                motivo: "falta el sujeto: antes del verbo debe haber un sintagma nominal o un interrogativo",
                columna: c.actual.columna
            )
        }
        partes.append("[V \(try verbo(&c))]")

        let hayPregunta = preg(&c)
        if hayPregunta { partes.append("[PREG]") }

        guard c.alFinal else {
            throw ErrorValidacion(
                motivo: "el verbo debe estar al final: después solo se admite la partícula de pregunta",
                columna: c.actual.columna
            )
        }
        if interrogativo != nil && !hayPregunta {
            throw ErrorValidacion(
                motivo: "con interrogativo, la partícula de pregunta al final es obligatoria",
                columna: c.actual.columna
            )
        }
        return partes.joined(separator: " ")
    }

    // MARK: - [<interrog>]

    func interrog(_ c: inout Cursor) throws -> String? {
        guard esInterrogativo(c.actual) else { return nil }
        return c.avanzar().texto
    }

    // MARK: - <sn>

    /// <sn> ::= <pronombre> | [<numero>] [<pronombre>] <nombre>
    /// Un pronombre seguido de un nombre se lee como poseedor + nombre cuando ya hay
    /// sujeto; si es el primer sintagma, el pronombre es el sujeto por sí solo.
    func sn(_ c: inout Cursor, haySujeto: Bool) throws -> String {
        let t = c.actual
        if esInterrogativo(t) {
            throw ErrorValidacion(motivo: "el interrogativo solo puede estar al inicio", columna: t.columna)
        }
        if esPregunta(t) {
            throw ErrorValidacion(motivo: "la partícula de pregunta solo puede estar al final", columna: t.columna)
        }

        if esPronombre(t) {
            let poseedor = haySujeto && c.siguiente.map { analizarNombre($0.texto) != nil && !esPronombre($0) } == true
            c.avanzar()
            guard poseedor else { return t.texto }
            return t.texto + " " + (try nombre(&c, despuesDeNumero: false).texto)
        }

        var partes: [String] = []
        var valor: Int?
        if cifras.pareceNumero(t.texto) {
            valor = try numero(&c)
            partes.append(t.texto)
        }
        if esPronombre(c.actual) {
            partes.append(c.avanzar().texto)
        }
        let n = try nombre(&c, despuesDeNumero: valor != nil)
        partes.append(n.texto)

        if let valor, valor > 1, !n.plural {
            throw ErrorValidacion(
                motivo: "con un número mayor que 1 (\(valor)) el nombre '\(n.texto)' debe llevar el sufijo de plural",
                columna: n.columna
            )
        }
        return partes.joined(separator: " ")
    }

    // MARK: - <nombre>

    func nombre(_ c: inout Cursor, despuesDeNumero: Bool) throws -> (texto: String, plural: Bool, columna: Int) {
        let t = c.actual
        guard t.tipo == .palabra, let plural = analizarNombre(t.texto) else {
            let motivo = despuesDeNumero ? "se esperaba un nombre después del número" : "se esperaba un nombre"
            throw ErrorValidacion(motivo: motivo, columna: t.columna)
        }
        c.avanzar()
        return (t.texto, plural, t.columna)
    }

    // MARK: - <verbo>

    func verbo(_ c: inout Cursor) throws -> String {
        guard esVerbo(c.actual) else {
            throw ErrorValidacion(motivo: "se esperaba el verbo", columna: c.actual.columna)
        }
        return c.avanzar().texto
    }

    // MARK: - <numero>

    func numero(_ c: inout Cursor) throws -> Int {
        let valor = try cifras.valor(de: c.actual)
        c.avanzar()
        return valor
    }

    // MARK: - [<preg>]

    func preg(_ c: inout Cursor) -> Bool {
        guard esPregunta(c.actual) else { return false }
        c.avanzar()
        return true
    }
}
