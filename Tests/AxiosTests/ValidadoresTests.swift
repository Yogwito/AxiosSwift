import XCTest
import Foundation
@testable import AxiosCore

final class ValidadoresTests: XCTestCase {
    /// BD con léxico, reglas y señales de las semanas 1 y 2, cargados desde data/.
    private static func bdCargada() throws -> BaseDatos {
        let bd = try BaseDatos(ruta: ":memory:")
        for archivo in ["lexico_v0.7.txt", "reglas_v0.7.txt", "senales_semana1.txt", "senales_semana2.txt"] {
            let r = try bd.cargar(archivo: archivoDatos(archivo))
            XCTAssertEqual(r.errores, [], archivo)
        }
        return bd
    }

    private var bd: BaseDatos!

    override func setUpWithError() throws {
        bd = try Self.bdCargada()
    }

    private func k(_ s: String) -> ResultadoValidacion { validarKethari(s, lexicon: bd) }
    private func o(_ s: String) -> ResultadoValidacion { validarOzh(s, lexicon: bd) }

    // MARK: - Señales reales

    func testTodasLasSenalesValidanEnSuLengua() throws {
        let senales = try bd.todasLasSenales().filter { $0.voz == "kethari" || $0.voz == "ozh" }
        XCTAssertEqual(senales.count, 20, "21 señales menos la desconocida")

        for s in senales {
            let r = s.voz == "kethari" ? k(s.transcripcion) : o(s.transcripcion)
            XCTAssertTrue(
                r.valida,
                "día \(s.dia) \(s.voz) '\(s.transcripcion)': \(r.motivo ?? "") (columna \(r.columna.map(String.init) ?? "-"))"
            )
        }
    }

    // MARK: - Kethari

    func testKethariRechaza() {
        let casos: [(frase: String, contiene: String)] = [
            ("kum ra-sel vinok", "nombre después del número"),
            ("ra-sel kum vinok", "plural"),
            ("ti-sab kumesh vinok", "cifra 'sab' no existe en Kethari"),
            ("kom ulesh vinime", "partícula de pregunta"),
            ("an vinime dahl", "el verbo debe estar al final"),
            ("an telescopio thal", "palabra desconocida 'telescopio'"),
            ("an#dahl thal", "carácter no válido '#'"),
            ("ra- kumesh vinok", "guion"),
            ("", "vacía"),
        ]
        for caso in casos {
            let r = k(caso.frase)
            XCTAssertFalse(r.valida, "'\(caso.frase)' debería ser inválida")
            XCTAssertTrue(r.motivo?.contains(caso.contiene) == true, "'\(caso.frase)': \(r.motivo ?? "nil")")
        }
    }

    func testKethariColumnas() {
        XCTAssertEqual(k("an telescopio thal").columna, 4)
        XCTAssertEqual(k("an#dahl thal").columna, 3)
        XCTAssertEqual(k("ti-sab kumesh vinok").columna, 4, "columna de la cifra inválida")
        XCTAssertEqual(k("ra- kumesh vinok").columna, 3, "columna del guion")
        XCTAssertEqual(k("an vinime dahl").columna, 11)
    }

    func testKethariValidasExtra() {
        for frase in ["an dahl thal", "ulesh anir vael kor ka"] {
            let r = k(frase)
            XCTAssertTrue(r.valida, "'\(frase)': \(r.motivo ?? "")")
        }
        XCTAssertEqual(k("ulesh anir vael kor ka").estructura, "[S ulesh] [O anir vael] [V kor] [PREG]")
    }

    func testKethariEstructura() {
        let r = k("ir yorr mi ka")
        XCTAssertTrue(r.valida, r.motivo ?? "")
        XCTAssertEqual(r.estructura, "[S ir] [O yorr] [V mi] [PREG]")
        XCTAssertEqual(k("kom ulesh vinime ka").estructura, "[INT kom] [S ulesh] [V vinime] [PREG]")
        XCTAssertEqual(k("sem ombra salok ka").estructura, "[S sem] [O ombra] [V salok] [PREG]")
        XCTAssertEqual(k("anul ti-vo lunesh tepime").estructura, "[S anul] [O ti-vo lunesh] [V tepime]")
    }

    func testKethariNumeroUnoNoExigePlural() {
        XCTAssertTrue(k("an ti kum kor").valida)
        XCTAssertFalse(k("an ra kum kor").valida)
        XCTAssertTrue(k("an ra kumesh kor").valida)
    }

    // MARK: - Ozh

    func testOzhRechaza() {
        let casos: [(frase: String, contiene: String)] = [
            ("sur ʔoka ois-ulo gor", "partícula justo después del verbo"),
            ("lom oruvi ilu", "partícula justo después del verbo"),
            ("lom zi", "falta el sujeto"),
            ("sur zi ʔenka wem", "prefijo de pregunta"),
            ("wem ʔasur mar shavi", "el interrogativo solo puede estar al final"),
            ("ʔoka venu sur zi oruvi", "una marca de tiempo"),
        ]
        for caso in casos {
            let r = o(caso.frase)
            XCTAssertFalse(r.valida, "'\(caso.frase)' debería ser inválida")
            XCTAssertTrue(r.motivo?.contains(caso.contiene) == true, "'\(caso.frase)': \(r.motivo ?? "nil")")
        }
    }

    func testOzhValidasYEstructura() {
        let r = o("ʔasur mar shavi wem")
        XCTAssertTrue(r.valida, r.motivo ?? "")
        XCTAssertEqual(r.estructura, "[V ʔasur] [P mar] [S shavi] [INT wem]")
        XCTAssertEqual(o("ʔanem tho shavi wis").estructura, "[V ʔanem] [P tho] [O shavi] [S wis]")

        let poseedor = o("ʔoka kesh zi oruvi thüm ʔenka")
        XCTAssertEqual(poseedor.estructura, "[T ʔoka] [V kesh] [P zi] [S oruvi] [O thüm ʔenka]")
        XCTAssertEqual(o("ne ʔim zi ʔenka gor").estructura, "[NEG] [V ʔim] [P zi] [S ʔenka] [O gor]")
    }

    func testOzhNoTienePlural() {
        let r = o("lom tho oruvi ilush")
        XCTAssertFalse(r.valida)
        XCTAssertEqual(r.motivo, "palabra desconocida 'ilush'")
    }

    // MARK: - Tokenizador (AFD)

    func testTokenizadorColumnas() throws {
        let tokens = try TokenizadorAlien.tokenizar("  ra-sel  ʔenka").get()
        XCTAssertEqual(tokens.map(\.texto), ["ra-sel", "ʔenka", ""])
        XCTAssertEqual(tokens.map(\.columna), [3, 11, 16])
        XCTAssertEqual(tokens.last?.tipo, .fin)
    }

    func testTokenizadorGuiones() {
        func error(_ s: String) -> ErrorLexicoAlien? {
            if case .failure(let e) = TokenizadorAlien.tokenizar(s) { return e }
            return nil
        }
        XCTAssertEqual(error("ra-"), ErrorLexicoAlien(motivo: "guion al final de una palabra", columna: 3))
        XCTAssertEqual(error("-sel"), ErrorLexicoAlien(motivo: "guion al inicio de una palabra", columna: 1))
        XCTAssertEqual(error("a--b"), ErrorLexicoAlien(motivo: "dos guiones seguidos", columna: 3))
        XCTAssertEqual(error("ab 3"), ErrorLexicoAlien(motivo: "carácter no válido '3'", columna: 4))
        XCTAssertNil(error("ra-sel drüm ʔa"))
    }

    // MARK: - Independencia del léxico

    func testFuncionaConLexiconFalso() {
        let falso = LexiconFalso(
            traducciones: [.kethari: ["0": "zo", "1": "un", "2": "do"]],
            reglas: [.kethari: ["sufijo_plural": "s", "particula_pregunta": "q", "base": "3", "separador_numero": "-"]],
            categorias: [.kethari: ["yo": "pronombre", "casa": "sustantivo", "ver": "verbo"]]
        )
        XCTAssertTrue(validarKethari("yo do casas ver q", lexicon: falso).valida)
        XCTAssertFalse(validarKethari("yo do casa ver", lexicon: falso).valida)
    }
}
