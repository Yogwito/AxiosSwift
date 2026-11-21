import XCTest
@testable import AxiosCore

/// No terminales de los sintagmas (sn, determinante, nominal, sv, verbo), llamados
/// directamente sobre un Parser.
final class SintagmasTests: XCTestCase {
    private func parser(_ frase: String) -> Parser {
        Parser(tokens: tokens(frase), lexicon: bdConVocabularioEspanol)
    }

    private func error(_ cuerpo: () throws -> Any) -> ErrorSintactico? {
        do {
            _ = try cuerpo()
            return nil
        } catch {
            return error as? ErrorSintactico
        }
    }

    // MARK: - <sn>

    func testSNPronombre() throws {
        let sn = try parser("ustedes").sn()
        XCTAssertEqual(sn.sn, SN(nucleo: .pronombre(Pronombre(lema: "ustedes", persona: 2, plural: true))))
        XCTAssertTrue(sn.esPronombre)
        XCTAssertEqual(sn.persona, 3, "concuerda con el verbo en 3.ª (pv=3)")
    }

    func testSNConArticuloSeDescartaElArticulo() throws {
        let sn = try parser("el mensaje").sn()
        XCTAssertEqual(sn.sn, SN(nucleo: .sustantivo(lema: "mensaje", plural: false)))
        XCTAssertFalse(sn.esPronombre)
        XCTAssertEqual(sn.persona, 3)
    }

    // R12: "el" sin nombre detrás es el pronombre "él".
    func testElSinNombreDetrasEsPronombre() throws {
        let p = parser("el una criatura")
        let el = try p.sn()
        XCTAssertEqual(el.sn, SN(nucleo: .pronombre(Pronombre(lema: "el", persona: 3, plural: false))))
        XCTAssertEqual(try p.sn().sn, SN(nucleo: .sustantivo(lema: "criatura", plural: false)))
    }

    // R11: el poseedor es el pronombre del posesivo.
    func testPosesivos() throws {
        XCTAssertEqual(
            try parser("nuestro mundo").sn().sn,
            SN(nucleo: .sustantivo(lema: "mundo", plural: false), poseedor: Pronombre(lema: "nosotros", persona: 1, plural: true))
        )
        XCTAssertEqual(try parser("su planeta").sn().sn.poseedor, Pronombre(lema: "el", persona: 3, plural: false))
        XCTAssertEqual(try parser("sus naves").sn().sn.plural, true)
    }

    // R1: cantidad con plural.
    func testCantidad() throws {
        XCTAssertEqual(try parser("15 naves").sn().sn, SN(nucleo: .sustantivo(lema: "nave", plural: true), cantidad: 15))
        XCTAssertEqual(try parser("1 nave").sn().sn.cantidad, 1)
        XCTAssertEqual(try parser("nuestras 3 naves").sn().sn.cantidad, 3)
        XCTAssertEqual(try parser("0 naves").sn().sn.cantidad, 0)
    }

    func testCantidadSinPluralEsError() {
        XCTAssertEqual(
            error { try self.parser("15 nave").sn() },
            ErrorSintactico(motivo: "con 15 el nombre va en plural: 'nave'", linea: 1, columna: 4)
        )
        XCTAssertEqual(error { try self.parser("1 naves").sn() }?.columna, 3)
    }

    func testCantidadFueraDeRango() {
        XCTAssertEqual(
            error { try self.parser("10000 naves").sn() },
            ErrorSintactico(motivo: "la cantidad 10000 pasa del máximo de 9999", linea: 1, columna: 1)
        )
    }

    // R2: el determinante concuerda con el nombre.
    func testDeterminanteQueNoConcuerdaEsError() {
        XCTAssertEqual(
            error { try self.parser("los nave").sn() },
            ErrorSintactico(motivo: "'los' no concuerda en número con 'nave'", linea: 1, columna: 5)
        )
        XCTAssertEqual(error { try self.parser("nuestros mundo").sn() }?.columna, 10)
    }

    func testSNSinNombreEsError() {
        XCTAssertEqual(
            error { try self.parser("15 llegan").sn() },
            ErrorSintactico(motivo: "se esperaba un nombre y llegó 'llegan'", linea: 1, columna: 4)
        )
    }

    // MARK: - <sv> y <verbo>

    func testVerboConVariasLecturas() throws {
        let v = try parser("enviamos").verbo()
        XCTAssertEqual(v.lecturas.map(\.tiempo), [.presente, .pasado])
        XCTAssertFalse(v.perifrastico)
    }

    func testNegacion() throws {
        let sv = try parser("no vimos").sv()
        XCTAssertEqual(sv.polaridad, .negativa)
        XCTAssertEqual(sv.verbo.lecturas, [RasgosVerbo(raiz: "ver", persona: 1, plural: true, tiempo: .pasado)])
    }

    // R9: "van a llegar" es llegar en futuro con la persona y el número de "van".
    func testPerifrasisIrA() throws {
        let p = parser("no van a llegar")
        let sv = try p.sv()
        XCTAssertEqual(sv.polaridad, .negativa)
        XCTAssertTrue(sv.verbo.perifrastico)
        XCTAssertEqual(sv.verbo.lecturas, [RasgosVerbo(raiz: "llegar", persona: 3, plural: true, tiempo: .futuro)])
        XCTAssertEqual(p.actual.tipo, .fin, "consume las tres palabras")
    }

    // "fueron a ver": ir en pasado no hace perífrasis (la fila dice t=presente).
    func testIrEnPasadoNoEsPerifrasis() throws {
        let p = parser("fueron a ver")
        let v = try p.verbo()
        XCTAssertFalse(v.perifrastico)
        XCTAssertEqual(v.lecturas.map(\.raiz), ["ser", "ir"])
        XCTAssertEqual(p.actual.texto, "a")
    }

    func testVanSinInfinitivoEsSoloIr() throws {
        let v = try parser("van").verbo()
        XCTAssertEqual(v.lecturas, [RasgosVerbo(raiz: "ir", persona: 3, plural: true, tiempo: .presente)])
    }

    func testSinVerboEsError() {
        XCTAssertEqual(
            error { try self.parser("no los vimos").sv() },
            ErrorSintactico(motivo: "se esperaba un verbo y llegó 'los'", linea: 1, columna: 4)
        )
        XCTAssertEqual(error { try self.parser("").verbo() }?.motivo, "se esperaba un verbo y llegó el final de la frase")
    }
}
