import Foundation

/// Por qué un generador no pudo escribir la oración en la lengua destino.
public enum ErrorGeneracion: Error, Equatable {
    /// El léxico no tiene la palabra española (lema) en esa lengua.
    case sinTraduccion(String, Lengua)
    /// Falta una regla de la lengua, o su valor no tiene sentido.
    case faltaRegla(String, Lengua)
}

/// Piezas comunes de los generadores: buscar palabras y reglas sin inventar nada,
/// reponer el sujeto omitido y colocar los constituyentes según la regla `orden`.
struct BaseGenerador {
    let lexicon: Lexicon
    let lengua: Lengua

    /// Traducción de un lema español; si no hay, es un error (nunca se inventa).
    func palabra(_ lema: String) throws -> String {
        guard let forma = lexicon.traduccion(es: lema, lengua: lengua, en: nil), !forma.isEmpty else {
            throw ErrorGeneracion.sinTraduccion(lema, lengua)
        }
        return forma
    }

    /// Valor obligatorio de una regla.
    func regla(_ clave: String) throws -> String {
        guard let valor = valorRegla(lexicon, clave, lengua) else {
            throw ErrorGeneracion.faltaRegla(clave, lengua)
        }
        return valor
    }

    /// Pronombre personal español con esa persona y número, sacado de `vocab_es`
    /// (filas `pronombre` con rasgos `p` y `n`). Se usa para reponer el sujeto
    /// omitido. Entre varios (él/ella) se toma el primero por orden alfabético,
    /// que en Kethari y Ozh se traducen igual.
    func pronombre(persona: Int, plural: Bool) throws -> Pronombre {
        let numero = plural ? "pl" : "sg"
        for forma in lexicon.vocabularioEspanol().sorted() {
            for entrada in lexicon.entradasEspanol(forma: forma)
            where entrada.categoria == Categoria.pronombre
                && entrada.rasgos["p"] == String(persona)
                && entrada.rasgos["n"] == numero
                && entrada.lemas.first == entrada.forma {
                return Pronombre(lema: entrada.forma, persona: persona, plural: plural)
            }
        }
        throw ErrorGeneracion.sinTraduccion("pronombre \(persona)\(numero)", lengua)
    }

    /// Pone `palabra` antes o después de `nucleo` según una regla de posición
    /// (`posicion_numero`, `posicion_poseedor`), cuyo valor es "antes" o "despues".
    func colocar(_ palabra: String, junto nucleo: String, regla clave: String) throws -> [String] {
        switch BaseDatos.clave(try regla(clave)) {
        case "antes": return [palabra, nucleo]
        case "despues": return [nucleo, palabra]
        default: throw ErrorGeneracion.faltaRegla(clave, lengua)
        }
    }

    /// Pone el interrogativo al principio o al final de la frase según
    /// `posicion_interrogativo` ("inicio" o "final").
    func colocarInterrogativo(_ interrogativo: String, en palabras: [String]) throws -> [String] {
        switch BaseDatos.clave(try regla("posicion_interrogativo")) {
        case "inicio": return [interrogativo] + palabras
        case "final": return palabras + [interrogativo]
        default: throw ErrorGeneracion.faltaRegla("posicion_interrogativo", lengua)
        }
    }

    /// Coloca sujeto, objeto y verbo en el orden de la regla `orden` ("SOV", "VSO"...).
    /// Los constituyentes vacíos (sin objeto) simplemente no aparecen.
    func ordenar(sujeto: [String], objeto: [String], verbo: [String]) throws -> [String] {
        let orden = try regla("orden")
        guard orden.count == 3, Set(orden) == Set("SOV") else {
            throw ErrorGeneracion.faltaRegla("orden", lengua)
        }
        return orden.flatMap { letra -> [String] in
            switch letra {
            case "S": return sujeto
            case "O": return objeto
            default: return verbo
            }
        }
    }
}
