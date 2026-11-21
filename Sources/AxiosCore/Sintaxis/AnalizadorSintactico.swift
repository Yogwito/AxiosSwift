// Analizador sintáctico del español (P2): de los tokens al árbol intermedio, según
// la BNF de docs/memoria.md.

import Foundation

public struct AnalizadorSintactico {
    /// Cantidad más grande que se acepta (regla R1). No es una regla del español ni
    /// de Kethari u Ozh: es el alcance que fija el enunciado ("cantidades hasta 9.999"),
    /// por eso es una constante y no un dato (bitácora 2026-11-21).
    public static let cantidadMaxima = 9_999

    let lexicon: Lexicon

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// Analiza una frase ya tokenizada (con o sin `.fin` al final) y devuelve su árbol,
    /// o el primer error con la columna del token donde ocurrió.
    public func analizar(_ tokens: [Token]) -> Result<Oracion, ErrorSintactico> {
        do {
            return .success(try Parser(tokens: tokens, lexicon: lexicon).entrada())
        } catch let error as ErrorSintactico {
            return .failure(error)
        } catch {
            // El parser solo lanza ErrorSintactico; esto no debería ocurrir.
            return .failure(ErrorSintactico(motivo: "\(error)", linea: 1, columna: 1))
        }
    }

    // MARK: - Punto de enganche para el pipeline (P1) y la CLI

    /// Nombres de las fases de P2 en la traza (`[nombre] salida`).
    public enum Fase {
        public static let morfologia = "morfologia"
        public static let clasificacion = "clasificacion"
        public static let sintaxis = "sintaxis"
        public static let arbol = "arbol"
    }

    /// Lo que el pipeline llama después del corrector: adapta los tokens
    /// (`AdaptadorTokens`), los analiza y agrega a `traza` una fase por cada paso de P2:
    ///
    ///     [morfologia]    Cuándo: — | llegan: llegar 3pl presente
    ///     [clasificacion] ¿ SIGNO · Cuándo INTERROG · llegan VERBO · ? SIGNO · FIN
    ///     [sintaxis]      entrada[¿] › clausula[Cuándo] › sintInterrog[Cuándo] › nucleo[llegan] › sv[llegan] › verbo[llegan]
    ///     [arbol]         parcial(cuando, circunstancial) · S: omitido · V: llegar 3pl presente · O: —
    ///
    /// Si el análisis falla, `[arbol]` lleva el error con su columna y `[sintaxis]` el
    /// recorrido hasta donde llegó.
    public func analizar(_ tokens: [Token], traza: inout Traza) -> Result<Oracion, ErrorSintactico> {
        let adaptados = AdaptadorTokens.adaptar(tokens)
        let parser = Parser(tokens: adaptados, lexicon: lexicon)

        traza.agregar(fase: Fase.morfologia, salida: parser.textoMorfologia())
        traza.agregar(fase: Fase.clasificacion, salida: parser.textoClasificacion())

        let resultado: Result<Oracion, ErrorSintactico>
        do {
            resultado = .success(try parser.entrada())
        } catch let error as ErrorSintactico {
            resultado = .failure(error)
        } catch {
            resultado = .failure(ErrorSintactico(motivo: "\(error)", linea: 1, columna: 1))
        }

        traza.agregar(fase: Fase.sintaxis, salida: parser.recorrido.joined(separator: " › "))
        switch resultado {
        case .success(let oracion): traza.agregar(fase: Fase.arbol, salida: oracion.texto())
        case .failure(let error): traza.agregar(fase: Fase.arbol, salida: "error · \(error.texto())")
        }
        return resultado
    }
}

// MARK: - Texto de las fases

extension Parser {
    /// Lo que la morfología dijo de cada palabra (sin volver a analizarla).
    func textoMorfologia() -> String {
        let etiquetas = tokens.indices.compactMap { i -> AnalisisToken? in
            guard tokens[i].tipo == .palabra else { return nil }
            let c = clases[i]
            return AnalisisToken(token: tokens[i], verbos: c.verbos, infinitivo: c.infinitivo, nominales: c.nominales)
        }
        return Morfologia.texto(etiquetas)
    }

    /// Los terminales de la BNF de cada token: "el ART/PRON", "15 NUM", "FIN".
    func textoClasificacion() -> String {
        zip(tokens, clases).map { token, c in
            switch token.tipo {
            case .fin: return "FIN"
            case .interrogacion: return "\(token.texto) SIGNO"
            case .numero: return "\(token.texto) NUM"
            case .palabra:
                var categorias: [String] = []
                if c.interrogativo != nil { categorias.append("INTERROG") }
                if c.pronombre != nil { categorias.append("PRON") }
                if c.articulo != nil { categorias.append("ART") }
                if c.posesivo != nil { categorias.append("POS") }
                if c.negacion { categorias.append("NEG") }
                if c.preposicion != nil { categorias.append("PREP") }
                if !c.nominales.isEmpty { categorias.append("SUST") }
                if !c.verbos.isEmpty { categorias.append("VERBO") }
                if c.infinitivo != nil { categorias.append("INF") }
                return "\(token.texto) \(categorias.isEmpty ? "desconocida" : categorias.joined(separator: "/"))"
            }
        }.joined(separator: " · ")
    }
}
