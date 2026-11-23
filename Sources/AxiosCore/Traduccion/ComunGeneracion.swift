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
    /// Si hay, las palabras sin respaldo se retienen aquí en vez de lanzar un error.
    var retenidas: Retenidas?

    init(lexicon: Lexicon, lengua: Lengua, retenidas: Retenidas? = nil) {
        self.lexicon = lexicon
        self.lengua = lengua
        self.retenidas = retenidas
    }

    /// Traducción de un lema español. Si no hay, nunca se inventa: se retiene entre
    /// corchetes (si se está reteniendo) o es un error.
    func palabra(_ lema: String) throws -> String {
        if let forma = lexicon.traduccion(es: lema, lengua: lengua, en: nil), !forma.isEmpty {
            return forma
        }
        guard let retenidas else { throw ErrorGeneracion.sinTraduccion(lema, lengua) }
        let enLexico = lexicon.traduccion(es: lema, lengua: .es, en: nil) != nil
        return retenidas.retener(PalabraSinRespaldo(
            palabra: lema, lengua: lengua, motivo: enLexico ? .sinFormaEnLaLengua : .noEstaEnElLexico
        ))
    }

    /// Número escrito en la lengua; si no se puede, se retiene en cifras o es un error.
    func numero(_ n: Int) throws -> String {
        do {
            return try ConversorNumeros(lexicon: lexicon, lengua: lengua).convertir(n)
        } catch let error as ErrorNumero {
            guard let retenidas else { throw error }
            return retenidas.retener(PalabraSinRespaldo(palabra: String(n), lengua: lengua, motivo: .numero(error)))
        }
    }

    /// Agrega un afijo a una forma, salvo que la forma esté retenida: la palabra
    /// española queda tal cual para que se vea qué parte no es de la lengua destino.
    func afijar(_ forma: String, _ afijo: () throws -> String, delante: Bool = false) rethrows -> String {
        guard !Retenidas.esRetenida(forma) else { return forma }
        return delante ? try afijo() + forma : forma + (try afijo())
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

    /// Sintagma nominal: número, poseedor y nombre, cada uno donde digan
    /// `posicion_numero` y `posicion_poseedor`. Cómo se marca el plural depende de
    /// la lengua, así que lo decide `pluralizar` (Kethari agrega un sufijo, Ozh nada).
    /// Los pronombres plurales ya son palabras propias del léxico (ulesh, shavi).
    func sintagma(_ sn: SN, pluralizar: (String) throws -> String) throws -> [String] {
        switch sn.nucleo {
        case .pronombre(let p):
            return [try palabra(p.lema)]
        case .sustantivo(let lema, let plural):
            // Un número mayor que 1 cuenta como plural aunque el árbol no lo marque.
            let enPlural = plural || (sn.cantidad ?? 0) > 1
            let nombre = try palabra(lema)
            var palabras = [enPlural && !Retenidas.esRetenida(nombre) ? try pluralizar(nombre) : nombre]
            if let poseedor = sn.poseedor {
                palabras = try colocar(try palabra(poseedor.lema), junto: palabras, regla: "posicion_poseedor")
            }
            if let cantidad = sn.cantidad {
                palabras = try colocar(try numero(cantidad), junto: palabras, regla: "posicion_numero")
            }
            return palabras
        }
    }

    /// Pone `palabra` antes o después de `nucleo` según una regla de posición
    /// (`posicion_numero`, `posicion_poseedor`), cuyo valor es "antes" o "despues".
    func colocar(_ palabra: String, junto nucleo: [String], regla clave: String) throws -> [String] {
        switch BaseDatos.clave(try regla(clave)) {
        case "antes": return [palabra] + nucleo
        case "despues": return nucleo + [palabra]
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
