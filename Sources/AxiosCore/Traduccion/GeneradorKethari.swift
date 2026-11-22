import Foundation

/// Escribe en Kethari una oración del árbol intermedio.
///
/// Todo sale del `Lexicon`: las palabras de la tabla `lexico` y el orden y los
/// afijos de las reglas de Kethari (`orden`, `sufijo_pasado`, `sufijo_futuro`).
/// Aquí no hay ninguna palabra ni afijo escrito.
public struct GeneradorKethari {
    let base: BaseGenerador

    public init(lexicon: Lexicon) {
        base = BaseGenerador(lexicon: lexicon, lengua: .kethari)
    }

    public func generar(_ oracion: Oracion) throws -> String {
        let sujeto = try self.sujeto(oracion)
        let objeto = try oracion.objeto.map { try sintagma($0) } ?? []
        let verbo = [try self.verbo(oracion.verbo)]
        return try base.ordenar(sujeto: sujeto, objeto: objeto, verbo: verbo).joined(separator: " ")
    }

    // MARK: - Constituyentes

    /// Kethari exige sujeto: si está omitido se repone con la persona y el número del verbo.
    private func sujeto(_ oracion: Oracion) throws -> [String] {
        switch oracion.sujeto {
        case .explicito(let sn):
            return try sintagma(sn)
        case .omitido, .interrogativo:
            let rasgos = oracion.verbo.rasgos
            return [try pronombre(base.pronombre(persona: rasgos.persona, plural: rasgos.plural))]
        }
    }

    /// Sintagma nominal: [número] nombre[-plural]. Los pronombres plurales ya son
    /// palabras propias del léxico (ulesh, iresh) y no llevan sufijo.
    private func sintagma(_ sn: SN) throws -> [String] {
        switch sn.nucleo {
        case .pronombre(let p):
            return [try pronombre(p)]
        case .sustantivo(let lema, let plural):
            // Regla 3.3.5: un número mayor que 1 exige plural en el nombre.
            let enPlural = plural || (sn.cantidad ?? 0) > 1
            var nombre = try base.palabra(lema)
            if enPlural { nombre += try base.regla("sufijo_plural") }
            guard let cantidad = sn.cantidad else { return [nombre] }
            let numero = try ConversorNumeros(lexicon: base.lexicon, lengua: .kethari).convertir(cantidad)
            return try base.colocar(numero, junto: nombre, regla: "posicion_numero")
        }
    }

    private func pronombre(_ p: Pronombre) throws -> String {
        try base.palabra(p.lema)
    }

    /// [negación-]raíz[-tiempo]: el presente no lleva sufijo.
    private func verbo(_ v: NodoVerbo) throws -> String {
        var forma = try base.palabra(v.rasgos.raiz)
        switch v.rasgos.tiempo {
        case .presente: break
        case .pasado: forma += try base.regla("sufijo_pasado")
        case .futuro: forma += try base.regla("sufijo_futuro")
        }
        if v.negado { forma = try base.regla("prefijo_negacion") + forma }
        return forma
    }
}
