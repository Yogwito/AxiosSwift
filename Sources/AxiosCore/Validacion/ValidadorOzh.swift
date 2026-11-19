import Foundation

/// Valida una frase en Ozh con un analizador descendente recursivo.
///
///     <oracion>   ::= [<tiempo>] [negacion] <verbo> <particula> <sn> {<sn>} [<interrog>]
///     <tiempo>    ::= marca_pasado | marca_futuro
///     <verbo>     ::= [prefijo_pregunta] raiz-verbo
///     <particula> ::= una de la regla "particulas"
///     <sn>        ::= <pronombre> | [<numero>] <nombre> [<pronombre>]
///     <numero>    ::= <cifra> { separador_numero <cifra> }
///
/// Las palabras, categorías, marcas y partículas salen del `Lexicon`.
/// No usa código de generación: solo el léxico, las reglas y el tokenizador.
public func validarOzh(_ s: String, lexicon: Lexicon) -> ResultadoValidacion {
    let analizador = AnalizadorOzh(lexicon: lexicon)
    return validar(s) { cursor in try analizador.oracion(&cursor) }
}

private struct AnalizadorOzh {
    let lexicon: Lexicon
    let cifras: Cifras
    let marcasTiempo: [String]
    let negacion: String?
    let prefijoPregunta: String?
    let particulas: [String]
    let interrogativosSujeto: [String]

    init(lexicon: Lexicon) {
        self.lexicon = lexicon
        cifras = Cifras(lexicon: lexicon, lengua: .ozh)
        marcasTiempo = ["marca_pasado", "marca_futuro"].compactMap { valorRegla(lexicon, $0, .ozh) }
        negacion = valorRegla(lexicon, "negacion", .ozh)
        prefijoPregunta = valorRegla(lexicon, "prefijo_pregunta", .ozh)
        particulas = listaRegla(lexicon, "particulas", .ozh)
        interrogativosSujeto = listaRegla(lexicon, "interrogativo_sujeto", .ozh)
    }

    // MARK: - Clasificación de palabras

    private func categoria(_ forma: String) -> String? {
        lexicon.categoria(forma: forma, lengua: .ozh)
    }

    func esTiempo(_ t: Token) -> Bool { t.tipo == .palabra && marcasTiempo.contains(t.texto) }
    func esNegacion(_ t: Token) -> Bool { t.tipo == .palabra && t.texto == negacion }
    func esParticula(_ t: Token) -> Bool { t.tipo == .palabra && particulas.contains(t.texto) }
    func esPronombre(_ t: Token) -> Bool { categoria(t.texto) == Categoria.pronombre }
    func esInterrogativo(_ t: Token) -> Bool { categoria(t.texto) == Categoria.interrogativo }
    func esNombre(_ t: Token) -> Bool { categoria(t.texto) == Categoria.sustantivo }

    /// Verbo: raíz verbo, o prefijo de pregunta + raíz verbo. Devuelve si lleva el prefijo.
    func analizarVerbo(_ t: Token) -> Bool? {
        guard t.tipo == .palabra else { return nil }
        if categoria(t.texto) == Categoria.verbo { return false }
        if let prefijo = prefijoPregunta, t.texto.hasPrefix(prefijo),
           categoria(String(t.texto.dropFirst(prefijo.count))) == Categoria.verbo {
            return true
        }
        return nil
    }

    func esConocida(_ t: Token) -> Bool {
        esTiempo(t) || esNegacion(t) || esParticula(t) || esPronombre(t) || esInterrogativo(t)
            || esNombre(t) || analizarVerbo(t) != nil || cifras.pareceNumero(t.texto)
    }

    // MARK: - <oracion>

    func oracion(_ c: inout Cursor) throws -> String {
        if let desconocida = c.tokens.first(where: { $0.tipo == .palabra && !esConocida($0) }) {
            throw ErrorValidacion(motivo: "palabra desconocida '\(desconocida.texto)'", columna: desconocida.columna)
        }

        var partes: [String] = []
        if let marca = tiempo(&c) { partes.append("[T \(marca)]") }
        if esTiempo(c.actual) {
            throw ErrorValidacion(motivo: "solo puede haber una marca de tiempo, al inicio", columna: c.actual.columna)
        }
        if esNegacion(c.actual) {
            c.avanzar()
            partes.append("[NEG]")
        }

        let v = try verbo(&c)
        partes.append("[V \(v.texto)]")
        partes.append("[P \(try particula(&c))]")

        var sintagmas: [String] = []
        while !c.alFinal && !esInterrogativo(c.actual) {
            sintagmas.append(try sn(&c))
        }
        if sintagmas.isEmpty {
            throw ErrorValidacion(
                motivo: "falta el sujeto: después de la partícula debe haber al menos un sintagma nominal",
                columna: c.actual.columna
            )
        }

        var interrogativo: String?
        if esInterrogativo(c.actual) {
            let t = c.avanzar()
            guard v.conPregunta else {
                throw ErrorValidacion(
                    motivo: "el interrogativo exige el prefijo de pregunta en el verbo", columna: t.columna
                )
            }
            guard c.alFinal else {
                throw ErrorValidacion(motivo: "el interrogativo solo puede estar al final", columna: c.actual.columna)
            }
            interrogativo = t.texto
        }

        // Si el interrogativo es sujeto (regla interrogativo_sujeto), todos los SN son objetos.
        let interrogativoEsSujeto = interrogativo.map(interrogativosSujeto.contains) ?? false
        for (i, texto) in sintagmas.enumerated() {
            partes.append("[\(i == 0 && !interrogativoEsSujeto ? "S" : "O") \(texto)]")
        }
        if let interrogativo {
            partes.append(interrogativoEsSujeto ? "[S \(interrogativo)]" : "[INT \(interrogativo)]")
        }
        return partes.joined(separator: " ")
    }

    // MARK: - [<tiempo>]

    func tiempo(_ c: inout Cursor) -> String? {
        guard esTiempo(c.actual) else { return nil }
        return c.avanzar().texto
    }

    // MARK: - <verbo>

    func verbo(_ c: inout Cursor) throws -> (texto: String, conPregunta: Bool) {
        let t = c.actual
        guard let conPregunta = analizarVerbo(t) else {
            let motivo: String
            if esTiempo(t) {
                motivo = "la marca de tiempo solo puede estar al inicio"
            } else if esInterrogativo(t) {
                motivo = "el interrogativo solo puede estar al final"
            } else if esNegacion(t) {
                motivo = "la negación va una sola vez, justo antes del verbo"
            } else {
                motivo = "se esperaba el verbo"
            }
            throw ErrorValidacion(motivo: motivo, columna: t.columna)
        }
        c.avanzar()
        return (t.texto, conPregunta)
    }

    // MARK: - <particula>

    func particula(_ c: inout Cursor) throws -> String {
        guard esParticula(c.actual) else {
            throw ErrorValidacion(motivo: "falta la partícula justo después del verbo", columna: c.actual.columna)
        }
        return c.avanzar().texto
    }

    // MARK: - <sn>

    /// <sn> ::= <pronombre> | [<numero>] <nombre> [<pronombre>]  (el poseedor va detrás)
    func sn(_ c: inout Cursor) throws -> String {
        let t = c.actual
        if esTiempo(t) {
            throw ErrorValidacion(motivo: "la marca de tiempo solo puede estar al inicio", columna: t.columna)
        }
        if esParticula(t) {
            throw ErrorValidacion(motivo: "la partícula va justo después del verbo", columna: t.columna)
        }
        if esNegacion(t) {
            throw ErrorValidacion(motivo: "la negación va justo antes del verbo", columna: t.columna)
        }
        if analizarVerbo(t) != nil {
            throw ErrorValidacion(motivo: "solo puede haber un verbo, al inicio de la oración", columna: t.columna)
        }

        if esPronombre(t) {
            return c.avanzar().texto
        }

        var partes: [String] = []
        if cifras.pareceNumero(t.texto) {
            _ = try numero(&c)
            partes.append(t.texto)
        }
        partes.append(try nombre(&c, despuesDeNumero: !partes.isEmpty))
        if esPronombre(c.actual) {
            partes.append(c.avanzar().texto)
        }
        return partes.joined(separator: " ")
    }

    // MARK: - <nombre>

    func nombre(_ c: inout Cursor, despuesDeNumero: Bool) throws -> String {
        let t = c.actual
        guard esNombre(t) else {
            let motivo = despuesDeNumero ? "se esperaba un nombre después del número" : "se esperaba un nombre"
            throw ErrorValidacion(motivo: motivo, columna: t.columna)
        }
        return c.avanzar().texto
    }

    // MARK: - <numero>

    func numero(_ c: inout Cursor) throws -> Int {
        let valor = try cifras.valor(de: c.actual)
        c.avanzar()
        return valor
    }
}
