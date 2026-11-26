import Foundation

/// Por qué un número no se pudo escribir en la lengua destino.
public enum ErrorNumero: Error, Equatable {
    /// Las reglas de la lengua no dicen en qué base cuenta.
    case faltaBase
    /// El léxico no tiene la palabra de esa cifra (nunca se inventa).
    case faltaCifra(Int)
    /// Negativo, o con más cifras de las que admite el validador (valor ≥ base^6).
    case fueraDeRango(Int)
}

/// Escribe un número en Kethari u Ozh.
///
/// No sabe nada de ninguna lengua en concreto: la base sale de la regla `base`,
/// el separador de `separador_numero` y cada cifra d de la traducción de la
/// palabra española "d". Así Kethari escribe 15 con dos cifras (ver señal 3 en
/// data/senales_semana1.txt) porque lo dicen los datos, no el código.
public struct ConversorNumeros {
    let lexicon: Lexicon
    let lengua: Lengua

    public init(lexicon: Lexicon, lengua: Lengua) {
        self.lexicon = lexicon
        self.lengua = lengua
    }

    public func convertir(_ numero: Int) throws -> String {
        guard let base = lexicon.regla("base", lengua: lengua).flatMap({ Int($0) }), base >= 2 else {
            throw ErrorNumero.faltaBase
        }
        let separador = lexicon.regla("separador_numero", lengua: lengua) ?? ""

        let digitos = try Self.digitos(de: numero, base: base)
        let palabras = try digitos.map { d -> String in
            guard let palabra = lexicon.traduccion(es: String(d), lengua: lengua, en: nil) else {
                throw ErrorNumero.faltaCifra(d)
            }
            return palabra
        }
        return palabras.joined(separator: separador)
    }

    /// Cifras de `numero` en `base`, de la más significativa a la menos.
    static func digitos(de numero: Int, base: Int) throws -> [Int] {
        guard numero >= 0 else { throw ErrorNumero.fueraDeRango(numero) }
        var resto = numero
        var digitos: [Int] = []
        repeat {
            digitos.insert(resto % base, at: 0)
            resto /= base
        } while resto > 0
        guard digitos.count <= Cifras.maximoCifras else { throw ErrorNumero.fueraDeRango(numero) }
        return digitos
    }
}
