import XCTest
import Foundation
@testable import AxiosCore

final class GeneradorOzhTests: XCTestCase {
    typealias A = Arbol

    /// Léxico y reglas de Ozh como en data/, con las claves que usa el árbol.
    static let lexicon = LexiconFalso(
        traducciones: [.ozh: [
            "yo": "ʔen", "tu": "sha", "el": "oru", "nosotros": "ʔenka",
            "ustedes": "shavi", "ellos": "oruvi", "ellas": "oruvi",
            "nave": "gor", "mensaje": "vesh", "paz": "ilu", "ciclo": "drüm",
            "llegar": "sur", "venir": "sur", "enviar": "dra", "querer": "lom", "esperar": "bo",
            "hablar": "tal", "ver": "ʔim",
        ]],
        reglas: [.ozh: [
            "orden": "VSO", "particulas": "zi,mar,tho",
            "particula_afirmacion": "zi", "particula_pregunta": "mar",
            "marca_pasado": "ʔoka", "marca_futuro": "venu", "negacion": "ne",
        ]],
        vocabulario: VocabPronombres.formas,
        vocabEs: VocabPronombres.filas
    )

    private func o(_ oracion: Oracion, _ lexicon: Lexicon = lexicon) throws -> String {
        try GeneradorOzh(lexicon: lexicon).generar(oracion)
    }

    // MARK: - Orden VSO con partícula

    /// "Ellos quieren paz" (señal 2): verbo, partícula, sujeto, objeto.
    func testOrdenVerboParticulaSujetoObjeto() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente), objeto: A.sust("paz"))
        XCTAssertEqual(try o(f), "lom zi oruvi ilu")
    }

    func testSinObjeto() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ustedes)), verbo: A.verbo("hablar", 2, plural: true, .presente))
        XCTAssertEqual(try o(f), "tal zi shavi")
    }

    /// Ozh también exige sujeto: "Queremos paz" repone ʔenka.
    func testSujetoOmitidoSeRepone() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .omitido, verbo: A.verbo("querer", 1, plural: true, .presente), objeto: A.sust("paz"))
        XCTAssertEqual(try o(f), "lom zi ʔenka ilu")
    }

    /// El orden sale de la regla `orden`; la partícula sigue pegada al verbo.
    func testElOrdenSaleDeLaRegla() throws {
        var lexicon = Self.lexicon
        lexicon.reglas[.ozh]?["orden"] = "SVO"
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)), verbo: A.verbo("esperar", 1, plural: false, .presente), objeto: A.sust("nave"))
        XCTAssertEqual(try o(f, lexicon), "ʔen bo zi gor")
    }

    // MARK: - Partícula obligatoria

    /// Decisión (bitácora 2026-11-22): la afirmación lleva `particula_afirmacion`.
    func testParticulaSaleDeLaRegla() throws {
        var lexicon = Self.lexicon
        lexicon.reglas[.ozh]?["particula_afirmacion"] = "tho"
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .presente), objeto: A.sust("mensaje"))
        XCTAssertEqual(try o(f, lexicon), "dra tho oru vesh")
    }

    /// Sin la regla no se inventa una partícula: la frase no se genera.
    func testSinParticulaEsError() {
        var lexicon = Self.lexicon
        lexicon.reglas[.ozh]?["particula_afirmacion"] = nil
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .presente))
        XCTAssertThrowsError(try o(f, lexicon)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .faltaRegla("particula_afirmacion", .ozh))
        }
    }

    /// La partícula elegida tiene que ser una de las de la regla `particulas`.
    func testParticulaQueNoEstaEnLaListaEsError() {
        var lexicon = Self.lexicon
        lexicon.reglas[.ozh]?["particula_afirmacion"] = "ka"
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .presente))
        XCTAssertThrowsError(try o(f, lexicon)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .faltaRegla("particula_afirmacion", .ozh))
        }
    }

    // MARK: - Tiempo

    /// El presente no lleva marca.
    func testPresenteSinMarca() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .presente), objeto: A.sust("mensaje"))
        XCTAssertEqual(try o(f), "dra zi oru vesh")
    }

    /// "Antes enviamos un mensaje" (señal 1): ʔoka abre la frase.
    func testPasadoConOka() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.nosotros)), verbo: A.verbo("enviar", 1, plural: true, .pasado), objeto: A.sust("mensaje"))
        XCTAssertEqual(try o(f), "ʔoka dra zi ʔenka vesh")
    }

    /// "Llegarán" (señal 3): venu abre la frase.
    func testFuturoConVenu() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("llegar", 3, plural: true, .futuro))
        XCTAssertEqual(try o(f), "venu sur zi oruvi")
    }

    /// Con sujeto omitido la marca sigue al inicio.
    func testFuturoConSujetoOmitido() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .omitido, verbo: A.verbo("esperar", 1, plural: true, .futuro))
        XCTAssertEqual(try o(f), "venu bo zi ʔenka")
    }

    func testFaltaMarcaDeTiempoEsError() {
        var lexicon = Self.lexicon
        lexicon.reglas[.ozh]?["marca_pasado"] = nil
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)), verbo: A.verbo("ver", 1, plural: false, .pasado))
        XCTAssertThrowsError(try o(f, lexicon)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .faltaRegla("marca_pasado", .ozh))
        }
    }

    // MARK: - Negación

    /// "Ellos no quieren paz" (señal 10) y "Ustedes no hablan" (señal 6): ne delante del verbo.
    func testNegacionConNe() throws {
        let f10 = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente, negado: true), objeto: A.sust("paz"))
        let f6 = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ustedes)), verbo: A.verbo("hablar", 2, plural: true, .presente, negado: true))
        XCTAssertEqual(try o(f10), "ne lom zi oruvi ilu")
        XCTAssertEqual(try o(f6), "ne tal zi shavi")
    }

    /// Tiempo y negación juntos: [marca] ne verbo, como en la BNF del validador.
    /// La señal 4 ("ne ʔim zi ʔenka gor", "No vimos…") no trae ʔoka; se sigue la regla
    /// `marca_pasado` y se toma la señal como excepción (bitácora 2026-11-22).
    func testPasadoNegativo() throws {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.nosotros)), verbo: A.verbo("ver", 1, plural: true, .pasado, negado: true), objeto: A.sust("nave"))
        XCTAssertEqual(try o(f), "ʔoka ne ʔim zi ʔenka gor")
    }

    func testVerboSinTraduccionEsError() {
        let f = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)), verbo: A.verbo("correr", 1, plural: false, .presente))
        XCTAssertThrowsError(try o(f)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .sinTraduccion("correr", .ozh))
        }
    }

    // MARK: - Datos reales

    private func bdCargada() throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt", "vocab_es_v0.7.txt"] {
            XCTAssertEqual(try bd.cargar(archivo: archivoDatos(archivo)).errores, [], archivo)
        }
        return bd
    }

    /// Con la BD cargada desde data/, la salida la acepta el validador de Ozh.
    func testConDatosRealesValida() throws {
        let bd = try bdCargada()
        let generador = GeneradorOzh(lexicon: bd)
        let casos: [(Oracion, String)] = [
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente), objeto: A.sust("paz")), "lom zi oruvi ilu"),
            (Oracion(tipo: .declarativa, sujeto: .omitido, verbo: A.verbo("querer", 1, plural: true, .presente), objeto: A.sust("paz")), "lom zi ʔenka ilu"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ustedes)), verbo: A.verbo("hablar", 2, plural: true, .presente)), "tal zi shavi"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.nosotros)), verbo: A.verbo("enviar", 1, plural: true, .pasado), objeto: A.sust("mensaje")), "ʔoka dra zi ʔenka vesh"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("llegar", 3, plural: true, .futuro)), "venu sur zi oruvi"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente, negado: true), objeto: A.sust("paz")), "ne lom zi oruvi ilu"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.nosotros)), verbo: A.verbo("ver", 1, plural: true, .pasado, negado: true), objeto: A.sust("nave")), "ʔoka ne ʔim zi ʔenka gor"),
        ]
        for (oracion, esperada) in casos {
            let frase = try generador.generar(oracion)
            XCTAssertEqual(frase, esperada)
            XCTAssertTrue(validarOzh(frase, lexicon: bd).valida, frase)
        }
    }
}
