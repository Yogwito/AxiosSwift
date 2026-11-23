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

    // MARK: - Ozh (base 10, cifras unidas con guion)

    /// Cifras y reglas de Ozh como en data/ (base 10: existen 0..9).
    private let ozh = LexiconFalso(
        traducciones: [.ozh: [
            "0": "zu", "1": "ois", "2": "dav", "3": "kru", "4": "fem",
            "5": "ulo", "6": "sab", "7": "nir", "8": "tok", "9": "hev",
        ]],
        reglas: [.ozh: ["base": "10", "separador_numero": "-"]]
    )

    private func o(_ n: Int) throws -> String {
        try ConversorNumeros(lexicon: ozh, lengua: .ozh).convertir(n)
    }

    /// Señal 7: seis = sab. En base 10 del 0 al 9 es una sola palabra.
    func testOzhUnaCifra() throws {
        XCTAssertEqual(try o(0), "zu")
        XCTAssertEqual(try o(6), "sab")
        XCTAssertEqual(try o(9), "hev")
    }

    /// Señal 3: quince = ois-ulo. Cada cifra decimal se escribe y se une con guion.
    func testOzhCuentaEnBaseDiezConGuiones() throws {
        XCTAssertEqual(try o(10), "ois-zu")
        XCTAssertEqual(try o(15), "ois-ulo")
        XCTAssertEqual(try o(26), "dav-sab")
        XCTAssertEqual(try o(100), "ois-zu-zu")
        XCTAssertEqual(try o(2026), "dav-zu-dav-sab")
    }

    /// El mismo número sale distinto en cada lengua porque cambia la base.
    func testMismoNumeroDistintaBase() throws {
        XCTAssertEqual(try k(15), "ra-sel")
        XCTAssertEqual(try o(15), "ois-ulo")
    }

    func testOzhLimiteDeSeisCifras() throws {
        XCTAssertEqual(try o(999_999), "hev-hev-hev-hev-hev-hev")
        XCTAssertThrowsError(try o(1_000_000)) { error in
            XCTAssertEqual(error as? ErrorNumero, .fueraDeRango(1_000_000))
        }
    }

    // MARK: - Datos reales

    private func bdCargada() throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt"] {
            XCTAssertEqual(try bd.cargar(archivo: archivoDatos(archivo)).errores, [], archivo)
        }
        return bd
    }

    /// Con los datos reales, la salida coincide con las señales 3 y 7 y la acepta el validador.
    func testOzhConDatosRealesValida() throws {
        let bd = try bdCargada()
        let conversor = ConversorNumeros(lexicon: bd, lengua: .ozh)
        XCTAssertEqual(try conversor.convertir(15), "ois-ulo")
        XCTAssertEqual(try conversor.convertir(6), "sab")
        let frase = "venu sur tho \(try conversor.convertir(15)) gor"
        XCTAssertTrue(validarOzh(frase, lexicon: bd).valida, frase)
    }

    /// Con los datos reales, la salida coincide con las señales y la acepta el validador.
    func testKethariConDatosRealesValida() throws {
        let bd = try bdCargada()
        let conversor = ConversorNumeros(lexicon: bd, lengua: .kethari)
        XCTAssertEqual(try conversor.convertir(15), "ra-sel")
        XCTAssertEqual(try conversor.convertir(6), "ti-vo")
        XCTAssertEqual(try conversor.convertir(26), "mok-ra")
        let frase = "anir \(try conversor.convertir(26)) sorinesh korok"
        XCTAssertTrue(validarKethari(frase, lexicon: bd).valida, frase)
    }
}
