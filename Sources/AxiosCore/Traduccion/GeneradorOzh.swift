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
        let verbo = [try self.verbo(oracion.verbo), try particula(oracion.tipo)]
        return try base.ordenar(sujeto: sujeto, objeto: objeto, verbo: verbo).joined(separator: " ")
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

    /// Ozh exige sujeto: si está omitido se repone con la persona y el número del verbo.
    private func sujeto(_ oracion: Oracion) throws -> [String] {
        switch oracion.sujeto {
        case .explicito(let sn):
            return try sintagma(sn)
        case .omitido, .interrogativo:
            let rasgos = oracion.verbo.rasgos
            return [try base.palabra(base.pronombre(persona: rasgos.persona, plural: rasgos.plural).lema)]
        }
    }

    private func sintagma(_ sn: SN) throws -> [String] {
        switch sn.nucleo {
        case .pronombre(let p):
            return [try base.palabra(p.lema)]
        case .sustantivo(let lema, _):
            return [try base.palabra(lema)]
        }
    }

    private func verbo(_ v: NodoVerbo) throws -> String {
        try base.palabra(v.rasgos.raiz)
    }
}
