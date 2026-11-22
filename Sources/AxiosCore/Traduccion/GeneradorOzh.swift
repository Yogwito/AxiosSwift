import Foundation

/// Escribe en Ozh una oración del árbol intermedio.
///
/// Todo sale del `Lexicon`: las palabras de la tabla `lexico` y el orden, las
/// partículas y las marcas de las reglas de Ozh. Aquí no hay ninguna palabra,
/// partícula ni marca escrita.
public struct GeneradorOzh {
    let base: BaseGenerador

    public init(lexicon: Lexicon) {
        base = BaseGenerador(lexicon: lexicon, lengua: .ozh)
    }

    public func generar(_ oracion: Oracion) throws -> String {
        let sujeto = try self.sujeto(oracion)
        let objeto = try oracion.objeto.map { try sintagma($0) } ?? []
        // La partícula es obligatoria y va justo después del verbo.
        let verbo = [try self.verbo(oracion.verbo, pregunta: oracion.tipo != .declarativa), try particula(oracion.tipo)]
        var cuerpo = try base.ordenar(sujeto: sujeto, objeto: objeto, verbo: verbo)
        if let interrogativo = oracion.interrogativo {
            // El interrogativo va donde diga `posicion_interrogativo` (final en Ozh).
            cuerpo = try base.colocarInterrogativo(try base.palabra(interrogativo.lema), en: cuerpo)
        }
        return (try inicio(oracion.verbo) + cuerpo).joined(separator: " ")
    }

    // MARK: - Tiempo y negación

    /// Lo que abre la frase: [marca de tiempo] [negación], en ese orden, como en la
    /// BNF del validador. El presente no tiene marca. El pasado lleva siempre
    /// `marca_pasado`, aunque la señal 4 no la traiga (bitácora 2026-11-22).
    private func inicio(_ v: NodoVerbo) throws -> [String] {
        var palabras: [String] = []
        switch v.rasgos.tiempo {
        case .presente: break
        case .pasado: palabras.append(try base.regla("marca_pasado"))
        case .futuro: palabras.append(try base.regla("marca_futuro"))
        }
        if v.negado { palabras.append(try base.regla("negacion")) }
        return palabras
    }

    // MARK: - Partícula

    /// Decisión (bitácora 2026-11-22): la afirmación lleva `particula_afirmacion` y
    /// la pregunta `particula_pregunta`. Tiene que ser una de la regla `particulas`.
    private func particula(_ tipo: TipoOracion) throws -> String {
        let clave: String
        switch tipo {
        case .declarativa: clave = "particula_afirmacion"
        case .preguntaSiNo, .preguntaParcial: clave = "particula_pregunta"
        }
        let particula = try base.regla(clave)
        guard listaRegla(base.lexicon, "particulas", .ozh).contains(particula) else {
            throw ErrorGeneracion.faltaRegla(clave, .ozh)
        }
        return particula
    }

    // MARK: - Constituyentes

    /// Ozh exige sujeto: si está omitido se repone con la persona y el número del
    /// verbo. Si el sujeto es el propio interrogativo ("¿Quién…?"), ya lo pone `generar`.
    private func sujeto(_ oracion: Oracion) throws -> [String] {
        switch oracion.sujeto {
        case .explicito(let sn):
            return try sintagma(sn)
        case .interrogativo:
            return []
        case .omitido:
            let rasgos = oracion.verbo.rasgos
            return [try base.palabra(base.pronombre(persona: rasgos.persona, plural: rasgos.plural).lema)]
        }
    }

    /// Sintagma nominal: [número] nombre [poseedor]. Ozh no marca el plural
    /// (`plural = no`): "quince naves" es "ois-ulo gor", con el nombre igual.
    private func sintagma(_ sn: SN) throws -> [String] {
        let marcaPlural = BaseDatos.clave(try base.regla("plural")) != "no"
        guard !marcaPlural else { throw ErrorGeneracion.faltaRegla("plural", .ozh) }
        return try base.sintagma(sn) { nombre in nombre }
    }

    /// Raíz del verbo; en cualquier pregunta (sí/no o parcial) lleva `prefijo_pregunta`.
    private func verbo(_ v: NodoVerbo, pregunta: Bool) throws -> String {
        let raiz = try base.palabra(v.rasgos.raiz)
        return pregunta ? try base.regla("prefijo_pregunta") + raiz : raiz
    }
}
