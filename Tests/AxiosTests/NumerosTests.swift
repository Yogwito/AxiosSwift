import XCTest
import Foundation
@testable import AxiosCore

final class NumerosTests: XCTestCase {
    /// Cifras y reglas de Kethari como en data/ (base 6: solo existen 0..5).
    private let kethari = LexiconFalso(
        traducciones: [.kethari: ["0": "vo", "1": "ti", "2": "ra", "3": "sel", "4": "mok", "5": "pai"]],
        reglas: [.kethari: ["base": "6", "separador_numero": "-"]]
    )

    private func k(_ n: Int, _ lexicon: Lexicon? = nil) throws -> String {
        try ConversorNumeros(lexicon: lexicon ?? kethari, lengua: .kethari).convertir(n)
    }

    func testKethariUnaCifra() throws {
        XCTAssertEqual(try k(0), "vo")
        XCTAssertEqual(try k(1), "ti")
        XCTAssertEqual(try k(5), "pai")
    }

    /// Señales 3, 7 y 10: quince = ra-sel, seis = ti-vo, veintiséis = mok-ra.
    func testKethariCuentaEnBaseSeis() throws {
        XCTAssertEqual(try k(6), "ti-vo")
        XCTAssertEqual(try k(15), "ra-sel")
        XCTAssertEqual(try k(26), "mok-ra")
        XCTAssertEqual(try k(35), "pai-pai")
        XCTAssertEqual(try k(36), "ti-vo-vo")
    }

    /// El límite es el mismo que aplica el validador: valor < base^6.
    func testKethariLimiteDeSeisCifras() throws {
        XCTAssertEqual(try k(46_655), "pai-pai-pai-pai-pai-pai")
        XCTAssertThrowsError(try k(46_656)) { error in
            XCTAssertEqual(error as? ErrorNumero, .fueraDeRango(46_656))
        }
    }

    func testNegativoNoSeTraduce() {
        XCTAssertThrowsError(try k(-1)) { error in
            XCTAssertEqual(error as? ErrorNumero, .fueraDeRango(-1))
        }
    }

    func testSinReglaDeBaseEsError() {
        let sinBase = LexiconFalso(traducciones: kethari.traducciones)
        XCTAssertThrowsError(try k(3, sinBase)) { error in
            XCTAssertEqual(error as? ErrorNumero, .faltaBase)
        }
    }

    /// Nunca inventa una cifra: si el léxico no la tiene, lo dice.
    func testCifraSinTraduccionEsError() {
        var incompleto = kethari
        incompleto.traducciones[.kethari]?["4"] = nil
        XCTAssertThrowsError(try k(26, incompleto)) { error in
            XCTAssertEqual(error as? ErrorNumero, .faltaCifra(4))
        }
    }

    /// Con los datos reales, la salida coincide con las señales y la acepta el validador.
    func testKethariConDatosRealesValida() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt"] {
            XCTAssertEqual(try bd.cargar(archivo: archivoDatos(archivo)).errores, [], archivo)
        }
        let conversor = ConversorNumeros(lexicon: bd, lengua: .kethari)
        XCTAssertEqual(try conversor.convertir(15), "ra-sel")
        XCTAssertEqual(try conversor.convertir(6), "ti-vo")
        XCTAssertEqual(try conversor.convertir(26), "mok-ra")
        let frase = "anir \(try conversor.convertir(26)) sorinesh korok"
        XCTAssertTrue(validarKethari(frase, lexicon: bd).valida, frase)
    }
}
