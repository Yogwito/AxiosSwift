import Foundation
@testable import AxiosCore

/// Atajos para armar árboles intermedios en los tests de los generadores,
/// tal como los entregaría el analizador sintáctico (lemas como claves, sin tildes).
enum Arbol {
    static func pron(_ lema: String, _ persona: Int, plural: Bool) -> Pronombre {
        Pronombre(lema: lema, persona: persona, plural: plural)
    }

    static func sn(_ pronombre: Pronombre) -> SN {
        SN(nucleo: .pronombre(pronombre))
    }

    static func sust(_ lema: String, plural: Bool = false, cantidad: Int? = nil, de poseedor: Pronombre? = nil) -> SN {
        SN(nucleo: .sustantivo(lema: lema, plural: plural), cantidad: cantidad, poseedor: poseedor)
    }

    static func verbo(
        _ raiz: String, _ persona: Int, plural: Bool, _ tiempo: Tiempo, negado: Bool = false
    ) -> NodoVerbo {
        NodoVerbo(
            rasgos: RasgosVerbo(raiz: raiz, persona: persona, plural: plural, tiempo: tiempo),
            polaridad: negado ? .negativa : .afirmativa
        )
    }

    static let yo = pron("yo", 1, plural: false)
    static let tu = pron("tu", 2, plural: false)
    static let el = pron("el", 3, plural: false)
    static let nosotros = pron("nosotros", 1, plural: true)
    static let ustedes = pron("ustedes", 2, plural: true)
    static let ellos = pron("ellos", 3, plural: true)
}

/// Pronombres personales de `vocab_es` (los mismos que data/vocab_es_v0.7.txt),
/// para que el generador pueda reponer un sujeto omitido sin BD.
enum VocabPronombres {
    static let filas: [EntradaVocab] = [
        EntradaVocab(fila: "yo", lema: "yo", categoria: "pronombre", rasgos: "p=1;n=sg"),
        EntradaVocab(fila: "tú", lema: "tú", categoria: "pronombre", rasgos: "p=2;n=sg"),
        EntradaVocab(fila: "usted", lema: "usted", categoria: "pronombre", rasgos: "p=2;n=sg;pv=3"),
        EntradaVocab(fila: "él", lema: "él", categoria: "pronombre", rasgos: "p=3;n=sg"),
        EntradaVocab(fila: "ella", lema: "ella", categoria: "pronombre", rasgos: "p=3;n=sg"),
        EntradaVocab(fila: "nosotros", lema: "nosotros", categoria: "pronombre", rasgos: "p=1;n=pl"),
        EntradaVocab(fila: "nosotras", lema: "nosotros", categoria: "pronombre", rasgos: "p=1;n=pl"),
        EntradaVocab(fila: "ustedes", lema: "ustedes", categoria: "pronombre", rasgos: "p=2;n=pl;pv=3"),
        EntradaVocab(fila: "ellos", lema: "ellos", categoria: "pronombre", rasgos: "p=3;n=pl"),
        EntradaVocab(fila: "ellas", lema: "ellas", categoria: "pronombre", rasgos: "p=3;n=pl"),
    ]

    static var formas: Set<String> { Set(filas.map(\.forma)) }
}
