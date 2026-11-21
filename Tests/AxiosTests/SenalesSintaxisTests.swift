import XCTest
@testable import AxiosCore

/// La salida en español del decodificador para las señales de los días 1 a 7
/// (data/senales_semana1.txt). Los números ya vienen en cifras, como los dejará el
/// analizador léxico de P1 ("quince" → 15), y sin el punto final.
///
/// Las que usan palabras fuera del alcance del enunciado (adverbios como "antes" o
/// "ya", clíticos como "los", "ninguna") se rechazan con la columna exacta: así el
/// límite de la gramática queda documentado con pruebas.
final class SenalesSintaxisTests: CasoSintaxis {
    // MARK: - Día 1

    func testDia1Kethari() throws {
        // "Nosotros enviamos mensajes." En la señal es pasado, pero "enviamos" también
        // es presente y nada en la frase lo decide: R6 se queda con la primera lectura.
        XCTAssertEqual(try arbol("Nosotros enviamos mensajes"), Oracion(
            tipo: .declarativa,
            sujeto: .explicito(pronombre("nosotros", 1, true)),
            verbo: verbo("enviar", 1, true, .presente),
            objeto: nombre("mensaje", plural: true)
        ))
    }

    func testDia1OzhFueraDeAlcance() {
        XCTAssertEqual(error("Antes enviamos un mensaje"),
                       ErrorSintactico(motivo: "palabra desconocida 'Antes'", linea: 1, columna: 1))
    }

    // MARK: - Día 2

    func testDia2() throws {
        let kethari = try arbol("Nosotros queremos paz")
        XCTAssertEqual(kethari.sujeto, .explicito(pronombre("nosotros", 1, true)))
        XCTAssertEqual(kethari.verbo, verbo("querer", 1, true, .presente))
        XCTAssertEqual(kethari.objeto, nombre("paz"))

        let ozh = try arbol("Ellos quieren paz")
        XCTAssertEqual(ozh.sujeto, .explicito(pronombre("ellos", 3, true)))
        XCTAssertEqual(ozh.verbo, verbo("querer", 3, true, .presente))
    }

    // MARK: - Día 3

    func testDia3() throws {
        XCTAssertEqual(try arbol("15 naves llegaron"), Oracion(
            tipo: .declarativa,
            sujeto: .explicito(nombre("nave", plural: true, cantidad: 15)),
            verbo: verbo("llegar", 3, true, .pasado)
        ))
        XCTAssertEqual(try arbol("Llegarán 15 naves").tipo, .declarativa)
    }

    // MARK: - Día 4

    func testDia4FueraDeAlcance() {
        // "Nosotros no los vimos a ustedes.": el clítico "los" no está en la gramática.
        XCTAssertEqual(error("Nosotros no los vimos a ustedes"),
                       ErrorSintactico(motivo: "se esperaba un verbo y llegó 'los'", linea: 1, columna: 13))
        XCTAssertEqual(error("No vimos ninguna nave"),
                       ErrorSintactico(motivo: "palabra desconocida 'ninguna'", linea: 1, columna: 10))
    }

    // MARK: - Día 5

    func testDia5() throws {
        let cuando = Interrogativo(lema: "cuando", funcion: .circunstancial)
        let ustedes = Sujeto.explicito(pronombre("ustedes", 2, true))
        XCTAssertEqual(try arbol("¿ Cuándo vendrán ustedes ?"), Oracion(
            tipo: .preguntaParcial(cuando), sujeto: ustedes, verbo: verbo("venir", 3, true, .futuro)
        ))
        XCTAssertEqual(try arbol("¿ Cuándo vienen ustedes ?"), Oracion(
            tipo: .preguntaParcial(cuando), sujeto: ustedes, verbo: verbo("venir", 3, true, .presente)
        ))
    }

    // MARK: - Día 6

    func testDia6() throws {
        XCTAssertEqual(try arbol("¿ Quién envió el mensaje ?").sujeto, .interrogativo)
        XCTAssertEqual(try arbol("Ustedes no hablan"), Oracion(
            tipo: .declarativa,
            sujeto: .explicito(pronombre("ustedes", 2, true)),
            verbo: verbo("hablar", 3, true, .presente, .negativa)
        ))
    }

    func testDia6DesconocidaFueraDeAlcance() {
        XCTAssertEqual(error("Ya los escuchamos"),
                       ErrorSintactico(motivo: "palabra desconocida 'Ya'", linea: 1, columna: 1))
    }

    // MARK: - Día 7

    func testDia7() throws {
        XCTAssertEqual(try arbol("Nosotros esperaremos 6 ciclos"), Oracion(
            tipo: .declarativa,
            sujeto: .explicito(pronombre("nosotros", 1, true)),
            verbo: verbo("esperar", 1, true, .futuro),
            objeto: nombre("ciclo", plural: true, cantidad: 6)
        ))
        XCTAssertEqual(try arbol("Yo espero 6 ciclos").verbo, verbo("esperar", 1, false, .presente))
    }
}
