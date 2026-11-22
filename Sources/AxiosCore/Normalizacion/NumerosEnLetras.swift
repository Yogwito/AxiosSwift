// Números en letras (P1): "dos mil quince" → "2015". Las palabras y sus valores están
// en data/numeros_es_v0.7.txt; aquí solo está cómo se combinan.

import Foundation

struct NumerosEnLetras {
    let lexicon: Lexicon

    /// Nombres del formato de los datos (como nombres de columnas, no son palabras).
    enum Formato {
        static let categoria = "numeral"
        static let valor = "v"
        static let tipo = "tipo"
        static let solo = "solo"
        static let compuesto = "compuesto"
    }

    enum Tipo: String {
        case unidad, decena, centena, mil, conector
    }

    struct Numeral {
        var tipo: Tipo
        var valor: Int
        /// No puede empezar un número ("una nave").
        var soloCompuesto: Bool
    }

    /// Dónde va la lectura del número dentro de un grupo de tres cifras.
    private enum Fase {
        case inicio, centena, decena, conector, unidad
    }

    func numeral(_ palabra: String) -> Numeral? {
        guard let fila = lexicon.entradasEspanol(forma: palabra).first(where: { $0.categoria == Formato.categoria }),
              let tipo = Tipo(rawValue: fila.rasgos[Formato.tipo] ?? "")
        else { return nil }
        return Numeral(
            tipo: tipo,
            valor: Int(fila.rasgos[Formato.valor] ?? "") ?? 0,
            soloCompuesto: fila.rasgos[Formato.solo] == Formato.compuesto
        )
    }

    /// Cambia cada número en letras por sus cifras. Las cifras toman la columna
    /// original de la primera palabra del número.
    func convertir(_ entrada: TextoNormalizado) -> TextoNormalizado {
        let caracteres = Array(entrada.texto)
        let palabras = NumerosEnLetras.palabras(caracteres)
        var salida: [Character] = []
        var columnas: [Int] = []
        var copiado = 0  // caracteres de la entrada ya copiados

        var i = 0
        while i < palabras.count {
            guard let leido = leer(desde: i, palabras: palabras, caracteres: caracteres) else {
                i += 1
                continue
            }
            let (valor, usadas) = leido
            let inicio = palabras[i].lowerBound
            salida += caracteres[copiado..<inicio]
            columnas += entrada.columnas[copiado..<inicio]
            for cifra in String(valor) {
                salida.append(cifra)
                columnas.append(entrada.columnas[inicio])
            }
            copiado = palabras[i + usadas - 1].upperBound
            i += usadas
        }
        salida += caracteres[copiado...]
        columnas += entrada.columnas[copiado...]

        return TextoNormalizado(texto: String(salida), columnas: columnas, longitudOriginal: entrada.longitudOriginal)
    }

    /// Lee el número más largo que empieza en la palabra `i`: su valor y cuántas palabras usa.
    private func leer(desde i: Int, palabras: [Range<Int>], caracteres: [Character]) -> (Int, Int)? {
        func texto(_ j: Int) -> String { String(caracteres[palabras[j]]) }
        // Dos palabras del mismo número van separadas solo por un espacio.
        func seguidas(_ j: Int) -> Bool {
            j > 0 && j < palabras.count && palabras[j].lowerBound == palabras[j - 1].upperBound + 1
                && caracteres[palabras[j - 1].upperBound] == " "
        }

        var total = 0, grupo = 0, fase = Fase.inicio, conMil = false, usadas = 0
        var j = i
        while j < palabras.count, j == i || seguidas(j), let n = numeral(texto(j)) {
            if j == i && n.soloCompuesto { break }
            var acepta = true
            switch n.tipo {
            case .unidad where n.valor == 0:
                // "cero" solo vale solo
                if j == i { return (0, 1) }
                acepta = false
            case .unidad where fase == .inicio || fase == .centena:
                grupo += n.valor
                fase = .unidad
            case .unidad where fase == .conector && n.valor <= 9:
                grupo += n.valor
                fase = .unidad
            case .decena where fase == .inicio || fase == .centena:
                grupo += n.valor
                fase = .decena
            case .centena where fase == .inicio && grupo == 0:
                grupo += n.valor
                fase = .centena
            case .mil where !conMil && fase != .conector:
                total += (grupo == 0 ? 1 : grupo) * n.valor
                grupo = 0
                fase = .inicio
                conMil = true
            case .conector where fase == .decena:
                // "y" solo si detrás viene una unidad del 1 al 9: "treinta y dos"
                guard seguidas(j + 1), let siguiente = numeral(texto(j + 1)),
                      siguiente.tipo == .unidad, (1...9).contains(siguiente.valor)
                else { acepta = false; break }
                fase = .conector
            default:
                acepta = false
            }
            if !acepta { break }
            usadas = j - i + 1
            j += 1
        }
        return usadas > 0 ? (total + grupo, usadas) : nil
    }

    /// Rangos de las palabras: tramos seguidos de letras.
    static func palabras(_ caracteres: [Character]) -> [Range<Int>] {
        var rangos: [Range<Int>] = []
        var inicio: Int?
        for (i, c) in caracteres.enumerated() {
            if c.isLetter {
                if inicio == nil { inicio = i }
            } else if let comienzo = inicio {
                rangos.append(comienzo..<i)
                inicio = nil
            }
        }
        if let comienzo = inicio {
            rangos.append(comienzo..<caracteres.count)
        }
        return rangos
    }
}
