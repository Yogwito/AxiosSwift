import XCTest
import Foundation
@testable import AxiosCore

final class GeneradorKethariTests: XCTestCase {
    typealias A = Arbol

    /// Léxico y reglas de Kethari como en data/, con las claves que usa el árbol.
    static let lexicon = LexiconFalso(
        traducciones: [.kethari: [
            "yo": "an", "tu": "ul", "el": "ir", "nosotros": "anir", "nosotros incluyente": "anul",
            "ustedes": "ulesh", "ellos": "iresh", "ellas": "iresh",
            "nave": "kum", "mensaje": "ombra", "paz": "parn", "ciclo": "lun",
            "llegar": "vin", "venir": "vin", "enviar": "sal", "querer": "thal", "esperar": "tep",
        ]],
        reglas: [.kethari: [
            "orden": "SOV", "sufijo_pasado": "ok", "sufijo_futuro": "ime",
        ]],
        vocabulario: VocabPronombres.formas,
        vocabEs: VocabPronombres.filas
    )

    private func k(_ oracion: Oracion, _ lexicon: Lexicon = lexicon) throws -> String {
        try GeneradorKethari(lexicon: lexicon).generar(oracion)
    }

    // MARK: - Orden SOV

    /// "Nosotros queremos paz." → sujeto, objeto, verbo.
    func testOrdenSujetoObjetoVerbo() throws {
        let o = Oracion(
            tipo: .declarativa, sujeto: .explicito(A.sn(A.nosotros)),
            verbo: A.verbo("querer", 1, plural: true, .presente), objeto: A.sust("paz")
        )
        XCTAssertEqual(try k(o), "anir parn thal")
    }

    /// Sin objeto: solo sujeto y verbo.
    func testSinObjeto() throws {
        let o = Oracion(
            tipo: .declarativa, sujeto: .explicito(A.sn(A.ustedes)),
            verbo: A.verbo("venir", 2, plural: true, .presente)
        )
        XCTAssertEqual(try k(o), "ulesh vin")
    }

    /// El orden sale de la regla `orden`, no del código: con "OVS" cambia la salida.
    func testElOrdenSaleDeLaRegla() throws {
        var lexicon = Self.lexicon
        lexicon.reglas[.kethari]?["orden"] = "OVS"
        let o = Oracion(
            tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)),
            verbo: A.verbo("querer", 1, plural: false, .presente), objeto: A.sust("paz")
        )
        XCTAssertEqual(try k(o, lexicon), "parn thal an")
    }

    func testOrdenInvalidoEsError() {
        var lexicon = Self.lexicon
        lexicon.reglas[.kethari]?["orden"] = "SVX"
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)), verbo: A.verbo("venir", 1, plural: false, .presente))
        XCTAssertThrowsError(try k(o, lexicon)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .faltaRegla("orden", .kethari))
        }
    }

    // MARK: - Sujeto obligatorio

    /// "Queremos paz": el sujeto está omitido y el generador repone el pronombre
    /// con la persona y el número del verbo, porque Kethari exige sujeto.
    func testSujetoOmitidoSeRepone() throws {
        let o = Oracion(
            tipo: .declarativa, sujeto: .omitido,
            verbo: A.verbo("querer", 1, plural: true, .presente), objeto: A.sust("paz")
        )
        XCTAssertEqual(try k(o), "anir parn thal")
    }

    func testSujetoOmitidoTerceraPlural() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .omitido, verbo: A.verbo("llegar", 3, plural: true, .pasado))
        XCTAssertEqual(try k(o), "iresh vinok")
    }

    // MARK: - Tiempo

    func testPresenteSinSufijo() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .presente), objeto: A.sust("mensaje"))
        XCTAssertEqual(try k(o), "ir ombra sal")
    }

    func testPasadoConSufijo() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .pasado), objeto: A.sust("mensaje"))
        XCTAssertEqual(try k(o), "ir ombra salok")
    }

    /// "Nosotros esperaremos" (señal 7): futuro con -ime.
    func testFuturoConSufijo() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.nosotros)), verbo: A.verbo("esperar", 1, plural: true, .futuro))
        XCTAssertEqual(try k(o), "anir tepime")
    }

    // MARK: - Nunca inventa

    func testVerboSinTraduccionEsError() {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)), verbo: A.verbo("correr", 1, plural: false, .presente))
        XCTAssertThrowsError(try k(o)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .sinTraduccion("correr", .kethari))
        }
    }

    func testFaltaSufijoDeTiempoEsError() {
        var lexicon = Self.lexicon
        lexicon.reglas[.kethari]?["sufijo_futuro"] = nil
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.yo)), verbo: A.verbo("venir", 1, plural: false, .futuro))
        XCTAssertThrowsError(try k(o, lexicon)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .faltaRegla("sufijo_futuro", .kethari))
        }
    }

    // MARK: - Datos reales

    /// Con la BD cargada desde data/, la salida la acepta el validador de Kethari.
    func testConDatosRealesValida() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt", "vocab_es_v0.7.txt"] {
            XCTAssertEqual(try bd.cargar(archivo: archivoDatos(archivo)).errores, [], archivo)
        }
        let generador = GeneradorKethari(lexicon: bd)
        let casos: [(Oracion, String)] = [
            (Oracion(tipo: .declarativa, sujeto: .omitido, verbo: A.verbo("querer", 1, plural: true, .presente), objeto: A.sust("paz")), "anir parn thal"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.el)), verbo: A.verbo("enviar", 3, plural: false, .pasado), objeto: A.sust("mensaje")), "ir ombra salok"),
            (Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ustedes)), verbo: A.verbo("venir", 2, plural: true, .futuro)), "ulesh vinime"),
        ]
        for (oracion, esperada) in casos {
            let frase = try generador.generar(oracion)
            XCTAssertEqual(frase, esperada)
            XCTAssertTrue(validarKethari(frase, lexicon: bd).valida, frase)
        }
    }
}
