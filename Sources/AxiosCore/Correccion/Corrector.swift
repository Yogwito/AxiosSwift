// Corrector ortográfico (P1): cambia una palabra mal escrita por la más cercana del
// vocabulario español, con una distancia de Levenshtein propia. Una palabra que el
// sistema ya reconoce no se toca.

import Foundation

public struct Corrector {
    let lexicon: Lexicon
    let morfologia: Morfologia

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
        self.morfologia = Morfologia(lexicon: lexicon)
    }

    /// Corrige las palabras; números, signos y fin no se tocan. Cada token conserva su columna.
    public func corregir(_ tokens: [Token]) -> (tokens: [Token], correcciones: [Correccion]) {
        let vocabulario = lexicon.vocabularioEspanol()
        var salida = tokens
        var correcciones: [Correccion] = []
        for (i, token) in tokens.enumerated() where token.tipo == .palabra {
            guard let c = correccion(de: token.texto, vocabulario: vocabulario) else { continue }
            salida[i].texto = c.corregida
            correcciones.append(c)
        }
        return (salida, correcciones)
    }

    func correccion(de palabra: String) -> Correccion? {
        correccion(de: palabra, vocabulario: lexicon.vocabularioEspanol())
    }

    /// La corrección de una palabra, o nil si es válida, si nada está lo bastante cerca
    /// o si hay empate (no se adivina).
    func correccion(de palabra: String, vocabulario: Set<String>) -> Correccion? {
        let clave = BaseDatos.clave(palabra)
        if vocabulario.contains(clave) || morfologia.reconoce(clave) { return nil }
        let umbral = Corrector.umbral(clave.count)
        guard umbral > 0 else { return nil }

        var mejor = umbral + 1
        var elegidas: [String] = []
        for candidata in candidatas(para: clave, vocabulario: vocabulario)
        where abs(candidata.count - clave.count) <= umbral {
            let d = Corrector.distancia(clave, candidata)
            if d < mejor {
                mejor = d
                elegidas = [candidata]
            } else if d == mejor {
                elegidas.append(candidata)
            }
        }
        guard mejor <= umbral, elegidas.count == 1 else { return nil }
        return Correccion(original: palabra, corregida: elegidas[0], distancia: mejor)
    }

    /// Cambios permitidos según la longitud: 2 letras o menos, ninguno; hasta 6, uno; más, dos.
    /// Dos cambios en una palabra corta ya es otra palabra ("tienen" no es "venen").
    static func umbral(_ longitud: Int) -> Int {
        longitud <= 2 ? 0 : (longitud <= 6 ? 1 : 2)
    }

    /// El vocabulario más las formas conjugadas y los plurales que terminan como la
    /// palabra: "lelgan" termina en "-an", así que se prueba "llegan" (llegar + -an).
    /// Solo se quedan las que la morfología reconoce.
    func candidatas(para palabra: String, vocabulario: Set<String>) -> Set<String> {
        let letras = Array(palabra)
        guard letras.count > 1 else { return vocabulario }
        let verbos = vocabulario.filter(morfologia.esVerbo)
        let sustantivos = vocabulario.filter {
            lexicon.categoria(forma: $0, lengua: .es) == Morfologia.Formato.sustantivo
        }

        var generadas = Set<String>()
        for corte in 1..<letras.count {
            let sufijo = String(letras[corte...])
            for fila in lexicon.entradasEspanol(forma: "-" + sufijo) {
                guard let categoria = fila.categoria else { continue }
                if categoria == Morfologia.Formato.terminacionPlural {
                    // El lema es lo que se quita al singular: luz → lu + ces
                    let repuesto = fila.lemas.first ?? ""
                    for s in sustantivos where s.hasSuffix(repuesto) {
                        generadas.insert(String(s.dropLast(repuesto.count)) + sufijo)
                    }
                } else if categoria.hasPrefix(Morfologia.Formato.prefijoTerminacion) {
                    for v in verbos {
                        let raiz: String
                        if fila.rasgos[Morfologia.Formato.base] == Morfologia.Formato.baseInfinitivo {
                            raiz = v
                        } else {
                            // El lema de la fila dice a qué clase se aplica: ar, er, ir
                            guard fila.lemas.contains(String(v.suffix(2))) else { continue }
                            raiz = String(v.dropLast(2))
                        }
                        if !raiz.isEmpty {
                            generadas.insert(raiz + sufijo)
                        }
                    }
                }
            }
        }
        return vocabulario.union(generadas.filter(morfologia.reconoce))
    }

    /// Mínimo de inserciones, borrados y sustituciones de letras para pasar de `a` a `b`.
    /// Programación dinámica guardando solo dos filas de la tabla.
    public static func distancia(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var anterior = Array(0...y.count)
        var actual = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            actual[0] = i
            for j in 1...y.count {
                let costo = x[i - 1] == y[j - 1] ? 0 : 1
                actual[j] = min(anterior[j] + 1, actual[j - 1] + 1, anterior[j - 1] + costo)
            }
            swap(&anterior, &actual)
        }
        return anterior[y.count]
    }

    /// "kuando → cuando (1) · lelgan → llegan (2)", o "sin cambios".
    public static func texto(_ correcciones: [Correccion]) -> String {
        guard !correcciones.isEmpty else { return "sin cambios" }
        return correcciones.map { "\($0.original) → \($0.corregida) (\($0.distancia))" }.joined(separator: " · ")
    }
}
