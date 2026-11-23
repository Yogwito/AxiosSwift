import XCTest
import Foundation
@testable import AxiosCore

/// Palabras sin respaldo: el generador nunca inventa una forma. La palabra española
/// queda entre corchetes en la frase y se explica por qué (bitácora 2026-11-22).
final class DesconocidasTests: XCTestCase {
    typealias A = Arbol

    /// Kethari con "tierra" en el léxico pero sin forma (celda vacía) y sin "correr".
    private var kethari: LexiconFalso {
        var l = GeneradorKethariTests.lexicon
        l.traducciones[.es] = ["tierra": "tierra", "paz": "paz"]
        return l
    }

    private func k(_ o: Oracion) throws -> Traduccion {
        try GeneradorKethari(lexicon: kethari).traducir(o)
    }

    // MARK: - Retener

    /// "Ellos no quieren tierra": la frase se genera con [tierra] y su explicación.
    func testRetieneLaPalabraEntreCorchetes() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente, negado: true), objeto: A.sust("tierra"))
        let t = try k(o)
        XCTAssertEqual(t.texto, "iresh [tierra] nuthal")
        XCTAssertEqual(t.sinRespaldo, [PalabraSinRespaldo(palabra: "tierra", lengua: .kethari, motivo: .sinFormaEnLaLengua)])
        XCTAssertFalse(t.completa)
    }

    /// Una traducción con todas sus palabras no retiene nada.
    func testTraduccionCompletaNoRetieneNada() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente), objeto: A.sust("paz"))
        let t = try k(o)
        XCTAssertEqual(t.texto, "iresh parn thal")
        XCTAssertEqual(t.sinRespaldo, [])
        XCTAssertTrue(t.completa)
    }

    /// La palabra retenida no lleva afijos: queda claro qué parte no es Kethari.
    func testLaPalabraRetenidaNoLlevaAfijos() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("correr", 3, plural: true, .pasado, negado: true), objeto: A.sust("tierra", plural: true))
        let t = try k(o)
        XCTAssertEqual(t.texto, "iresh [tierra] [correr]")
        XCTAssertEqual(t.sinRespaldo.map(\.palabra), ["tierra", "correr"])
    }

    /// Distingue una palabra que no está en el léxico de una que no tiene forma en la lengua.
    func testMotivoSegunElLexico() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("correr", 3, plural: true, .presente))
        XCTAssertEqual(try k(o).sinRespaldo, [PalabraSinRespaldo(palabra: "correr", lengua: .kethari, motivo: .noEstaEnElLexico)])
    }

    /// Un número que no se puede escribir se retiene en cifras.
    func testNumeroNoRepresentableSeRetiene() throws {
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sust("nave", plural: true, cantidad: 50_000)), verbo: A.verbo("llegar", 3, plural: true, .pasado))
        let t = try k(o)
        XCTAssertEqual(t.texto, "[50000] kumesh vinok")
        XCTAssertEqual(t.sinRespaldo, [PalabraSinRespaldo(palabra: "50000", lengua: .kethari, motivo: .numero(.fueraDeRango(50_000)))])
    }

    /// En Ozh igual: el prefijo de pregunta no se pega a la palabra retenida.
    func testOzhTambienRetiene() throws {
        let o = Oracion(tipo: .preguntaSiNo, sujeto: .explicito(A.sn(A.ustedes)), verbo: A.verbo("correr", 2, plural: true, .presente))
        let t = try GeneradorOzh(lexicon: GeneradorOzhTests.lexicon).traducir(o)
        XCTAssertEqual(t.texto, "[correr] mar shavi")
        XCTAssertEqual(t.sinRespaldo.map(\.lengua), [.ozh])
    }

    /// Una regla que falta no es una palabra: sigue siendo un error.
    func testFaltaDeReglaSigueSiendoError() {
        var lexicon = kethari
        lexicon.reglas[.kethari]?["orden"] = nil
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("correr", 3, plural: true, .presente))
        XCTAssertThrowsError(try GeneradorKethari(lexicon: lexicon).traducir(o)) { error in
            XCTAssertEqual(error as? ErrorGeneracion, .faltaRegla("orden", .kethari))
        }
    }

    // MARK: - Explicar

    func testExplicaciones() {
        XCTAssertEqual(
            PalabraSinRespaldo(palabra: "tierra", lengua: .kethari, motivo: .sinFormaEnLaLengua).explicacion,
            "tierra: está en el léxico pero no tiene forma vigente en Kethari"
        )
        XCTAssertEqual(
            PalabraSinRespaldo(palabra: "correr", lengua: .ozh, motivo: .noEstaEnElLexico).explicacion,
            "correr: no está en el léxico, no se puede traducir a Ozh"
        )
        XCTAssertEqual(
            PalabraSinRespaldo(palabra: "50000", lengua: .kethari, motivo: .numero(.fueraDeRango(50_000))).explicacion,
            "50000: el número no se puede escribir en Kethari (tiene más cifras de las permitidas)"
        )
        XCTAssertEqual(
            PalabraSinRespaldo(palabra: "26", lengua: .kethari, motivo: .numero(.faltaCifra(4))).explicacion,
            "26: el número no se puede escribir en Kethari (falta la cifra 4 en el léxico)"
        )
    }

    // MARK: - Datos reales

    /// Tras la corrección de la semana 2 (teka: tierra → territorio reclamado), "tierra"
    /// ya no tiene forma vigente en Kethari: se retiene y el validador no la acepta.
    /// En Ozh "tierra" sigue siendo "mak".
    func testTierraTrasLaCorreccionDeLaSemana2() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt", "vocab_es_v0.7.txt", "senales_semana1.txt", "senales_semana2.txt"] {
            XCTAssertEqual(try bd.cargar(archivo: archivoDatos(archivo)).errores, [], archivo)
        }
        let o = Oracion(tipo: .declarativa, sujeto: .explicito(A.sn(A.ellos)), verbo: A.verbo("querer", 3, plural: true, .presente, negado: true), objeto: A.sust("tierra"))

        let kethari = try GeneradorKethari(lexicon: bd).traducir(o)
        XCTAssertEqual(kethari.texto, "iresh [tierra] nuthal")
        XCTAssertEqual(kethari.sinRespaldo.map(\.motivo), [.sinFormaEnLaLengua])
        XCTAssertFalse(validarKethari(kethari.texto, lexicon: bd).valida)

        let ozh = try GeneradorOzh(lexicon: bd).traducir(o)
        XCTAssertEqual(ozh.texto, "ne lom zi oruvi mak")
        XCTAssertTrue(ozh.completa)
        XCTAssertTrue(validarOzh(ozh.texto, lexicon: bd).valida)
    }
}
