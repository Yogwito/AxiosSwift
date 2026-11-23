import XCTest
import Foundation
@testable import AxiosCore

/// Ocho pares español → Kethari / Ozh con números y posesivos, de punta a punta:
/// la frase pasa por el analizador sintáctico (P2), los dos generadores (P3) y los
/// dos validadores (P4), con los datos reales de data/. Los números llegan en cifras,
/// como los deja el normalizador de P1.
final class ParesTests: XCTestCase {
    private struct Par {
        let espanol: String
        let kethari: String
        let ozh: String
    }

    private let pares: [Par] = [
        // Señal 3: número en base 6 / base 10; plural -esh en Kethari, sin plural en Ozh.
        Par(espanol: "15 naves llegaron", kethari: "ra-sel kumesh vinok", ozh: "ʔoka sur zi ois-ulo gor"),
        // Señal 7: seis es "ti-vo" (1·6 + 0) en Kethari y una sola cifra en Ozh.
        Par(espanol: "nosotros esperaremos 6 ciclos", kethari: "anir ti-vo lunesh tepime", ozh: "venu bo zi ʔenka sab drüm"),
        // Señal 10: 26 = 4·6 + 2.
        Par(espanol: "nosotros vimos 26 estrellas", kethari: "anir mok-ra sorinesh korok", ozh: "ʔoka ʔim zi ʔenka dav-sab ral"),
        // Tres cifras en base 6: 36 = 1·36 + 0·6 + 0.
        Par(espanol: "36 naves llegarán", kethari: "ti-vo-vo kumesh vinime", ozh: "venu sur zi kru-sab gor"),
        // Señal 8: el poseedor va delante en Kethari y detrás en Ozh.
        Par(espanol: "ellos visitaron nuestro mundo", kethari: "iresh anir vael dunok", ozh: "ʔoka kesh zi oruvi thüm ʔenka"),
        // Posesivo en el sujeto.
        Par(espanol: "mi nave llegó", kethari: "an kum vinok", ozh: "ʔoka sur zi gor ʔen"),
        // Número y posesivo juntos: [número] [poseedor] nombre / [número] nombre [poseedor].
        Par(espanol: "nuestras 12 naves llegarán", kethari: "ra-vo anir kumesh vinime", ozh: "venu sur zi ois-dav gor ʔenka"),
        // Número y posesivo en una pregunta: ka al final en Kethari, interrogativo al final en Ozh.
        Par(espanol: "¿ cuándo llegarán nuestras 5 naves ?", kethari: "kom pai anir kumesh vinime ka", ozh: "venu ʔasur mar ulo gor ʔenka wem"),
    ]

    func testOchoParesDeNumerosYPosesivos() throws {
        let bd = bdConVocabularioEspanol
        let analizador = AnalizadorSintactico(lexicon: bd)
        let kethari = GeneradorKethari(lexicon: bd)
        let ozh = GeneradorOzh(lexicon: bd)

        XCTAssertEqual(pares.count, 8)
        for par in pares {
            let oracion: Oracion
            switch analizador.analizar(tokens(par.espanol)) {
            case .success(let o): oracion = o
            case .failure(let error):
                XCTFail("\(par.espanol): \(error)")
                continue
            }

            let k = try kethari.traducir(oracion)
            XCTAssertEqual(k.texto, par.kethari, par.espanol)
            XCTAssertTrue(k.completa, par.espanol)
            XCTAssertTrue(validarKethari(k.texto, lexicon: bd).valida, "\(par.espanol) → \(k.texto)")

            let o = try ozh.traducir(oracion)
            XCTAssertEqual(o.texto, par.ozh, par.espanol)
            XCTAssertTrue(o.completa, par.espanol)
            XCTAssertTrue(validarOzh(o.texto, lexicon: bd).valida, "\(par.espanol) → \(o.texto)")
        }
    }
}
