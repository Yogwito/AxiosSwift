import XCTest
@testable import AxiosCore

/// Base de las pruebas del analizador sintáctico: solo utilidades, sin tests propios
/// (así las subclases no repiten pruebas).
class CasoSintaxis: XCTestCase {
    let analizador = AnalizadorSintactico(lexicon: bdConVocabularioEspanol)

    func arbol(_ frase: String, file: StaticString = #filePath, line: UInt = #line) throws -> Oracion {
        switch analizador.analizar(tokens(frase)) {
        case .success(let oracion): return oracion
        case .failure(let error):
            XCTFail("'\(frase)' → \(error.texto())", file: file, line: line)
            throw error
        }
    }

    func error(_ frase: String) -> ErrorSintactico? {
        if case .failure(let error) = analizador.analizar(tokens(frase)) { return error }
        return nil
    }

    func verbo(
        _ raiz: String, _ persona: Int, _ plural: Bool, _ tiempo: Tiempo,
        _ polaridad: Polaridad = .afirmativa, perifrastico: Bool = false
    ) -> NodoVerbo {
        NodoVerbo(
            rasgos: RasgosVerbo(raiz: raiz, persona: persona, plural: plural, tiempo: tiempo),
            polaridad: polaridad, perifrastico: perifrastico
        )
    }

    func pronombre(_ lema: String, _ persona: Int, _ plural: Bool) -> SN {
        SN(nucleo: .pronombre(Pronombre(lema: lema, persona: persona, plural: plural)))
    }

    func nombre(_ lema: String, plural: Bool = false, cantidad: Int? = nil, poseedor: Pronombre? = nil) -> SN {
        SN(nucleo: .sustantivo(lema: lema, plural: plural), cantidad: cantidad, poseedor: poseedor)
    }
}
