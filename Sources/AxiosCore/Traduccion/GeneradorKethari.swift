import Foundation

/// Escribe en Kethari una oración del árbol intermedio.
///
/// Todo sale del `Lexicon`: las palabras de la tabla `lexico` y el orden y los
/// afijos de las reglas de Kethari (`orden`, `sufijo_pasado`, `sufijo_futuro`).
/// Aquí no hay ninguna palabra ni afijo escrito.
public struct GeneradorKethari {
    var base: BaseGenerador

    public init(lexicon: Lexicon) {
        base = BaseGenerador(lexicon: lexicon, lengua: .kethari)
    }

    /// Como `generar`, pero una palabra sin respaldo no detiene la traducción: queda
    /// en español entre corchetes y se explica en `sinRespaldo`. Nunca se inventa.
    public func traducir(_ oracion: Oracion) throws -> Traduccion {
        let retenidas = Retenidas()
        var copia = self
        copia.base.retenidas = retenidas
        return Traduccion(texto: try copia.generar(oracion), sinRespaldo: retenidas.palabras)
    }

    /// La frase en Kethari; una palabra sin respaldo es un error.
    public func generar(_ oracion: Oracion) throws -> String {
        let sujeto = try self.sujeto(oracion)
        let objeto = try oracion.objeto.map { try sintagma($0) } ?? []
        let verbo = [try self.verbo(oracion.verbo)]
        var palabras = try base.ordenar(sujeto: sujeto, objeto: objeto, verbo: verbo)

        switch oracion.tipo {
        case .declarativa:
            break
        case .preguntaSiNo:
            palabras.append(try base.regla("particula_pregunta"))
        case .preguntaParcial(let interrogativo):
            // El interrogativo va donde diga `posicion_interrogativo` (inicio en
            // Kethari) y la partícula de pregunta cierra la frase.
            palabras = try base.colocarInterrogativo(try base.palabra(interrogativo.lema), en: palabras)
            palabras.append(try base.regla("particula_pregunta"))
        }
        return palabras.joined(separator: " ")
    }

    // MARK: - Constituyentes

    /// Kethari exige sujeto: si está omitido se repone con la persona y el número del
    /// verbo. Si el sujeto es el propio interrogativo ("¿Quién…?"), ya lo pone `generar`.
    private func sujeto(_ oracion: Oracion) throws -> [String] {
        switch oracion.sujeto {
        case .explicito(let sn):
            return try sintagma(sn)
        case .interrogativo:
            return []
        case .omitido:
            let rasgos = oracion.verbo.rasgos
            return [try pronombre(base.pronombre(persona: rasgos.persona, plural: rasgos.plural))]
        }
    }

    /// Sintagma nominal: [número] [poseedor] nombre[-plural]. Regla 3.3.5: un número
    /// mayor que 1 exige el sufijo de plural en el nombre.
    private func sintagma(_ sn: SN) throws -> [String] {
        try base.sintagma(sn) { nombre in nombre + (try base.regla("sufijo_plural")) }
    }

    /// Pronombre personal (también el poseedor) por su lema en el léxico.
    /// "nosotros" da siempre la forma Kethari de "nosotros" (excluyente): el español no
    /// distingue si el oyente está incluido, así que la de "nosotros incluyente" no se
    /// genera (bitácora 2026-11-22).
    private func pronombre(_ p: Pronombre) throws -> String {
        try base.palabra(p.lema)
    }

    /// [negación-]raíz[-tiempo]: el presente no lleva sufijo.
    private func verbo(_ v: NodoVerbo) throws -> String {
        var forma = try base.palabra(v.rasgos.raiz)
        switch v.rasgos.tiempo {
        case .presente: break
        case .pasado: forma = try base.afijar(forma) { try base.regla("sufijo_pasado") }
        case .futuro: forma = try base.afijar(forma) { try base.regla("sufijo_futuro") }
        }
        if v.negado { forma = try base.afijar(forma, { try base.regla("prefijo_negacion") }, delante: true) }
        return forma
    }
}
