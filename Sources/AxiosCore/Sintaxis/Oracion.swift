// No terminales de la oración:
//   <entrada>       ::= [SIGNO] <clausula> [SIGNO] FIN
//   <clausula>      ::= <sint-interrog> <nucleo> | <nucleo>
//   <sint-interrog> ::= [PREP] INTERROG [<nominal>]
//   <nucleo>        ::= [<sn>] <sv> [<sn>] [<sn>]
// y la construcción del árbol intermedio con las reglas R3 a R8.

import Foundation

/// `<sint-interrog>` ya analizado.
struct SintInterrogAnalizado {
    var token: Token
    var fila: EntradaVocab
    var conPreposicion: Bool
    var nombre: AnalisisNominal?
}

/// `<nucleo>` ya analizado: sintagma de delante, verbo y sintagmas de detrás.
struct NucleoAnalizado {
    var antes: SNAnalizado?
    var sv: SVAnalizado
    var despues: [SNAnalizado]
}

struct ClausulaAnalizada {
    var interrogativo: SintInterrogAnalizado?
    var nucleo: NucleoAnalizado
}

extension Parser {
    // MARK: - <entrada>

    /// `<entrada> ::= [SIGNO] <clausula> [SIGNO] FIN`. Antes de analizar se comprueba
    /// que todas las palabras se conozcan: la primera que no, se informa con su columna.
    func entrada() throws -> Oracion {
        visitar("entrada")
        if let desconocida = tokens.indices.first(where: { tokens[$0].tipo == .palabra && !clases[$0].esConocida }) {
            throw ErrorSintactico("palabra desconocida \(describir(tokens[desconocida]))", en: tokens[desconocida])
        }
        var conSigno = false
        if actual.tipo == .interrogacion {
            avanzar()
            conSigno = true
        }
        let clausula = try self.clausula()
        if actual.tipo == .interrogacion {
            avanzar()
            conSigno = true
        }
        guard actual.tipo == .fin else {
            throw error("sobra \(describir(actual)): se esperaba el final de la frase")
        }
        return try construir(clausula, conSigno: conSigno)
    }

    // MARK: - <clausula>

    /// `<clausula> ::= <sint-interrog> <nucleo> | <nucleo>`: empieza por interrogativo
    /// si el token es INTERROG, o PREP seguido de INTERROG ("a quién").
    func clausula() throws -> ClausulaAnalizada {
        visitar("clausula")
        let empiezaInterrogativo = claseActual.interrogativo != nil
            || (claseActual.preposicion != nil && clase(en: 1).interrogativo != nil)
        let interrogativo = empiezaInterrogativo ? try sintInterrog() : nil
        return ClausulaAnalizada(interrogativo: interrogativo, nucleo: try nucleo())
    }

    // MARK: - <sint-interrog>

    /// `<sint-interrog> ::= [PREP] INTERROG [<nominal>]`. El nombre se toma solo si la
    /// palabra no es también un verbo (R12: con dudas, se prefiere la lectura verbal
    /// mientras no haya verbo).
    func sintInterrog() throws -> SintInterrogAnalizado {
        visitar("sintInterrog")
        var conPreposicion = false
        if claseActual.preposicion != nil {
            avanzar()
            conPreposicion = true
        }
        let token = actual
        guard let fila = claseActual.interrogativo else {
            throw error("se esperaba una palabra interrogativa y llegó \(describir(token))")
        }
        avanzar()
        var nombre: AnalisisNominal?
        if !claseActual.nominales.isEmpty && claseActual.verbos.isEmpty {
            nombre = try nominal().0
        }
        return SintInterrogAnalizado(token: token, fila: fila, conPreposicion: conPreposicion, nombre: nombre)
    }

    // MARK: - <nucleo>

    /// `<nucleo> ::= [<sn>] <sv> [<sn>] [<sn>]`. Delante del verbo se espera un `<sn>`
    /// solo si la palabra no es NEG ni VERBO (R12: se prefiere la lectura verbal).
    func nucleo() throws -> NucleoAnalizado {
        visitar("nucleo")
        var antes: SNAnalizado?
        if empiezaSN && !claseActual.negacion && claseActual.verbos.isEmpty {
            antes = try sn()
        }
        let sv = try self.sv()
        var despues: [SNAnalizado] = []
        while despues.count < 2 && empiezaSN {
            despues.append(try sn())
        }
        return NucleoAnalizado(antes: antes, sv: sv, despues: despues)
    }

    // MARK: - Construcción del árbol (R3 a R8)

    func construir(_ clausula: ClausulaAnalizada, conSigno: Bool) throws -> Oracion {
        let nucleo = clausula.nucleo
        let verbo = nucleo.sv.verbo
        var lecturas = verbo.lecturas
        var detras = nucleo.despues
        var sujeto = Sujeto.omitido
        var inversionConPronombre = false

        func concuerdan(_ persona: Int, _ plural: Bool) -> [RasgosVerbo] {
            lecturas.filter { $0.persona == persona && $0.plural == plural }
        }
        func concuerdan(_ sn: SNAnalizado) -> [RasgosVerbo] {
            concuerdan(sn.persona, sn.plural)
        }

        // R3: el sintagma de delante es el sujeto y tiene que concordar con el verbo.
        if let delante = nucleo.antes {
            let validas = concuerdan(delante)
            guard !validas.isEmpty else {
                throw ErrorSintactico(
                    "el sujeto \(describir(delante.token)) no concuerda con el verbo \(describir(verbo.token))",
                    en: verbo.token
                )
            }
            sujeto = .explicito(delante.sn)
            lecturas = validas
        } else if let i = detras.firstIndex(where: { $0.esPronombre && !concuerdan($0).isEmpty }) {
            // R4: un pronombre de detrás que concuerda es el sujeto ("¿Vienen ustedes?").
            let pronombre = detras.remove(at: i)
            lecturas = concuerdan(pronombre)
            sujeto = .explicito(pronombre.sn)
            inversionConPronombre = true
        }

        // R5: la función del interrogativo sale del rasgo f de vocab_es.
        var interrogativo: Interrogativo?
        var objeto: SN?
        if let i = clausula.interrogativo {
            let funcion: FuncionInterrogativo
            switch i.fila.rasgos[FormatoSintaxis.funcion].flatMap(FuncionInterrogativo.init(rawValue:)) {
            case .circunstancial:
                funcion = .circunstancial
                if i.nombre != nil {
                    throw ErrorSintactico("\(describir(i.token)) no lleva un nombre detrás", en: i.token)
                }
            case .objeto:
                funcion = .objeto
            case .sujeto:
                // Sujeto si no hay otro sujeto, no lleva preposición y concuerda con el verbo.
                let plural = i.nombre?.plural ?? i.fila.plural ?? false
                let validas = concuerdan(Parser.personaNominal, plural)
                if sujeto == .omitido && !i.conPreposicion && !validas.isEmpty {
                    funcion = .sujeto
                    lecturas = validas
                    sujeto = i.nombre.map { .explicito(SN(nucleo: .sustantivo(lema: $0.lema, plural: $0.plural))) }
                        ?? .interrogativo
                } else {
                    funcion = .objeto
                }
            case nil:
                throw ErrorSintactico("falta el rasgo f del interrogativo \(describir(i.token)) en vocab_es", en: i.token)
            }
            // "¿Cuántos ciclos esperarán?": el nombre del interrogativo es el objeto.
            if funcion == .objeto, let nombre = i.nombre {
                objeto = SN(nucleo: .sustantivo(lema: nombre.lema, plural: nombre.plural))
            }
            interrogativo = Interrogativo(lema: i.fila.lemaPreferido, funcion: funcion)
        }

        // R4: si sigue sin sujeto, el primer sintagma de detrás que concuerda lo es
        // ("Llegarán quince naves"); el que no concuerda es el objeto ("Queremos paz").
        if sujeto == .omitido, let i = detras.firstIndex(where: { !concuerdan($0).isEmpty }) {
            let nuevo = detras.remove(at: i)
            lecturas = concuerdan(nuevo)
            sujeto = .explicito(nuevo.sn)
        }
        let interrogativoEsObjeto = interrogativo?.funcion == .objeto
        for sobrante in detras {
            if objeto != nil || interrogativoEsObjeto {
                throw ErrorSintactico(
                    "sobra \(describir(sobrante.token)): la oración ya tiene objeto", en: sobrante.token
                )
            }
            objeto = sobrante.sn
        }

        // R6 y R7: entre las lecturas que concuerdan, la primera en el orden de los datos.
        // Si no hay sujeto, queda omitido y su persona y número son los del verbo.
        guard let elegida = lecturas.first else {
            throw ErrorSintactico("ninguna lectura de \(describir(verbo.token)) concuerda con la frase", en: verbo.token)
        }

        // R8: tipo de oración.
        let tipo: TipoOracion
        if let interrogativo {
            tipo = .preguntaParcial(interrogativo)
        } else if conSigno || inversionConPronombre {
            tipo = .preguntaSiNo
        } else {
            tipo = .declarativa
        }

        return Oracion(
            tipo: tipo,
            sujeto: sujeto,
            verbo: NodoVerbo(rasgos: elegida, polaridad: nucleo.sv.polaridad, perifrastico: verbo.perifrastico),
            objeto: objeto
        )
    }
}
