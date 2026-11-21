// No terminales de los sintagmas:
//   <sn>           ::= PRON | [<determinante>] [NUM] <nominal>
//   <determinante> ::= ART | POS
//   <nominal>      ::= SUST
//   <sv>           ::= [NEG] <verbo>
//   <verbo>        ::= VERBO_PERIF PREP INF | VERBO

import Foundation

extension Parser {
    // MARK: - <sn>

    /// `<sn> ::= PRON | [<determinante>] [NUM] <nominal>`, con R1, R2, R11 y R12.
    func sn() throws -> SNAnalizado {
        let inicio = actual
        let c = claseActual

        // R12: "el"/"tu" son determinante si los sigue NUM o SUST; si no, pronombre.
        let llevaDeterminante = (c.articulo != nil || c.posesivo != nil) && esCantidadONombre(en: 1)
        if !llevaDeterminante, let fila = c.pronombre {
            guard let persona = fila.persona, let plural = fila.plural else {
                throw error("faltan la persona o el número del pronombre \(describir(inicio)) en vocab_es")
            }
            avanzar()
            let pronombre = Pronombre(lema: fila.lemaPreferido, persona: persona, plural: plural)
            return SNAnalizado(
                sn: SN(nucleo: .pronombre(pronombre)), token: inicio, esPronombre: true,
                persona: fila.personaConcordancia ?? persona, plural: plural
            )
        }

        let determinante = (c.articulo != nil || c.posesivo != nil) ? try self.determinante() : nil

        var cantidad: Int?
        if case .numero(let n) = actual.tipo {
            // R1: el alcance del proyecto son cantidades de 0 a 9 999.
            guard (0...AnalizadorSintactico.cantidadMaxima).contains(n) else {
                throw error("la cantidad \(n) pasa del máximo de \(AnalizadorSintactico.cantidadMaxima)")
            }
            cantidad = n
            avanzar()
        }

        let (lectura, tokenNombre) = try nominal()

        // R1: con un número distinto de 1 el nombre va en plural; con 1, en singular.
        if let cantidad, (cantidad != 1) != lectura.plural {
            throw ErrorSintactico(
                cantidad == 1
                    ? "con 1 el nombre va en singular: \(describir(tokenNombre))"
                    : "con \(cantidad) el nombre va en plural: \(describir(tokenNombre))",
                en: tokenNombre
            )
        }
        // R2: el determinante y el nombre concuerdan en número.
        if let determinante, let plural = determinante.plural, plural != lectura.plural {
            throw ErrorSintactico(
                "\(describir(determinante.token)) no concuerda en número con \(describir(tokenNombre))",
                en: tokenNombre
            )
        }
        return SNAnalizado(
            sn: SN(
                nucleo: .sustantivo(lema: lectura.lema, plural: lectura.plural),
                cantidad: cantidad,
                poseedor: determinante?.poseedor
            ),
            token: inicio, esPronombre: false, persona: Parser.personaNominal, plural: lectura.plural
        )
    }

    // MARK: - <determinante>

    /// `<determinante> ::= ART | POS`. R11: el poseedor es el pronombre del lema.
    func determinante() throws -> DeterminanteAnalizado {
        let token = actual
        if let posesivo = claseActual.posesivo {
            guard let poseedor = clasificador.pronombre(lema: posesivo.lemaPreferido) else {
                throw error("el posesivo \(describir(token)) no apunta a ningún pronombre de vocab_es")
            }
            avanzar()
            return DeterminanteAnalizado(token: token, plural: posesivo.plural, poseedor: poseedor)
        }
        if let articulo = claseActual.articulo {
            avanzar()
            return DeterminanteAnalizado(token: token, plural: articulo.plural, poseedor: nil)
        }
        throw error("se esperaba un artículo o un posesivo y llegó \(describir(token))")
    }

    // MARK: - <nominal>

    /// `<nominal> ::= SUST`. Si hay varias lecturas se usa la primera.
    func nominal() throws -> (AnalisisNominal, Token) {
        guard let lectura = claseActual.nominales.first else {
            throw error("se esperaba un nombre y llegó \(describir(actual))")
        }
        return (lectura, avanzar())
    }

    // MARK: - <sv>

    /// `<sv> ::= [NEG] <verbo>`. R10: NEG da polaridad negativa.
    func sv() throws -> SVAnalizado {
        var polaridad = Polaridad.afirmativa
        if claseActual.negacion {
            avanzar()
            polaridad = .negativa
        }
        return SVAnalizado(verbo: try verbo(), polaridad: polaridad)
    }

    // MARK: - <verbo>

    /// `<verbo> ::= VERBO_PERIF PREP INF | VERBO`. R9: la perífrasis sale de vocab_es
    /// (`ir|a|perifrasis|t=presente;resultado=futuro`): el verbo con ese lema y ese
    /// tiempo, seguido de la preposición del lema y un infinitivo, es el infinitivo en
    /// el tiempo `resultado`, con la persona y el número del verbo.
    func verbo() throws -> VerboAnalizado {
        let token = actual
        let lecturas = claseActual.verbos
        guard !lecturas.isEmpty else {
            throw error("se esperaba un verbo y llegó \(describir(token))")
        }

        if let preposicion = clase(en: 1).preposicion, let infinitivo = clase(en: 2).infinitivo {
            let perifrasticas: [RasgosVerbo] = lecturas.flatMap { lectura in
                clasificador.perifrasis(de: lectura.rasgos.raiz).compactMap { fila -> RasgosVerbo? in
                    guard fila.rasgos[FormatoSintaxis.tiempo] == lectura.rasgos.tiempo.rawValue,
                          fila.lemas.contains(preposicion),
                          let resultado = Tiempo(rawValue: fila.rasgos[FormatoSintaxis.resultado] ?? "")
                    else { return nil }
                    return RasgosVerbo(
                        raiz: infinitivo, persona: lectura.rasgos.persona,
                        plural: lectura.rasgos.plural, tiempo: resultado
                    )
                }
            }
            if !perifrasticas.isEmpty {
                avanzar()  // VERBO_PERIF
                avanzar()  // PREP
                avanzar()  // INF
                return VerboAnalizado(lecturas: perifrasticas, perifrastico: true, token: token)
            }
        }

        avanzar()
        return VerboAnalizado(lecturas: lecturas.map(\.rasgos), perifrastico: false, token: token)
    }
}
