import Foundation

/// Una palabra que no tiene respaldo en los datos de la lengua destino. El generador
/// nunca inventa una forma: la retiene en español, entre corchetes, y la explica.
public struct PalabraSinRespaldo: Equatable {
    public enum Motivo: Equatable {
        /// La palabra española no está en el léxico.
        case noEstaEnElLexico
        /// Está en el léxico, pero no tiene forma vigente en esa lengua (celda vacía
        /// o significado cerrado por una corrección, como la CORRECCION de Kethari en
        /// data/senales_semana2.txt).
        case sinFormaEnLaLengua
        /// Un número que no se puede escribir con las cifras y la base de la lengua.
        case numero(ErrorNumero)
    }

    /// Como la escribió el árbol (lema o cifras): "tierra", "50000".
    public var palabra: String
    public var lengua: Lengua
    public var motivo: Motivo

    public init(palabra: String, lengua: Lengua, motivo: Motivo) {
        self.palabra = palabra
        self.lengua = lengua
        self.motivo = motivo
    }

    /// Una línea para el usuario y para la traza.
    public var explicacion: String {
        switch motivo {
        case .noEstaEnElLexico:
            return "\(palabra): no está en el léxico, no se puede traducir a \(lengua.nombre)"
        case .sinFormaEnLaLengua:
            return "\(palabra): está en el léxico pero no tiene forma vigente en \(lengua.nombre)"
        case .numero(let error):
            let causa: String
            switch error {
            case .faltaBase: causa = "falta la regla de base"
            case .faltaCifra(let d): causa = "falta la cifra \(d) en el léxico"
            case .fueraDeRango: causa = "tiene más cifras de las permitidas"
            }
            return "\(palabra): el número no se puede escribir en \(lengua.nombre) (\(causa))"
        }
    }
}

/// Resultado de traducir una oración: la frase (con las palabras sin respaldo
/// retenidas entre corchetes) y la explicación de cada una.
public struct Traduccion: Equatable {
    public var texto: String
    public var sinRespaldo: [PalabraSinRespaldo]

    public init(texto: String, sinRespaldo: [PalabraSinRespaldo] = []) {
        self.texto = texto
        self.sinRespaldo = sinRespaldo
    }

    /// true si todas las palabras se pudieron traducir.
    public var completa: Bool { sinRespaldo.isEmpty }
}

/// Acumula las palabras retenidas durante una traducción.
final class Retenidas {
    private(set) var palabras: [PalabraSinRespaldo] = []

    /// Anota la palabra y devuelve cómo queda en la frase: entre corchetes.
    func retener(_ palabra: PalabraSinRespaldo) -> String {
        palabras.append(palabra)
        return Retenidas.marca(palabra.palabra)
    }

    static func marca(_ palabra: String) -> String { "[\(palabra)]" }

    /// Una forma retenida: ninguna forma del léxico empieza por "[".
    static func esRetenida(_ forma: String) -> Bool { forma.hasPrefix("[") }
}
