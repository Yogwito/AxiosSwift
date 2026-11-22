import XCTest
@testable import AxiosCore

final class NumerosEnLetrasTests: XCTestCase {
    /// Lexicon sin BD con las filas reales de data/numeros_es_v0.7.txt.
    private func lexiconDeNumeros() throws -> LexiconFalso {
        let contenido = try String(contentsOf: archivoDatos("numeros_es_v0.7.txt"), encoding: .utf8)
        let filas = contenido.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { linea -> EntradaVocab in
                let c = linea.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                return EntradaVocab(fila: c[0], lema: c[1], categoria: c[2], rasgos: c[3])
            }
        return LexiconFalso(vocabEs: filas)
    }

    private func texto(_ entrada: String) throws -> String {
        Normalizador(lexicon: try lexiconDeNumeros()).normalizar(entrada).texto
    }

    func testUnidadesYDecenas() throws {
        XCTAssertEqual(try texto("quince"), "15")
        XCTAssertEqual(try texto("cero"), "0")
        XCTAssertEqual(try texto("veintiséis estrellas"), "26 estrellas")
        XCTAssertEqual(try texto("veintiseis"), "26", "sin tilde también")
        XCTAssertEqual(try texto("treinta y dos"), "32")
    }

    func testCentenas() throws {
        XCTAssertEqual(try texto("cien"), "100")
        XCTAssertEqual(try texto("ciento uno"), "101")
        XCTAssertEqual(try texto("doscientas naves"), "200 naves")
        XCTAssertEqual(try texto("novecientos noventa y nueve"), "999")
    }

    func testMiles() throws {
        XCTAssertEqual(try texto("mil"), "1000")
        XCTAssertEqual(try texto("mil uno"), "1001")
        XCTAssertEqual(try texto("dos mil quince"), "2015")
        XCTAssertEqual(try texto("nueve mil novecientos noventa y nueve"), "9999")
    }

    func testFrasesDelEnunciado() throws {
        XCTAssertEqual(try texto("¿Llegaron quince naves?"), "¿llegaron 15 naves?")
        XCTAssertEqual(try texto("Esperaremos SEIS ciclos"), "esperaremos 6 ciclos")
        XCTAssertEqual(try texto("¿quince?"), "¿15?", "el signo pegado no impide convertir")
    }

    func testMasDeNueveMilSeConvierteYLoRechazaElSintactico() throws {
        XCTAssertEqual(try texto("diez mil"), "10000")
    }

    func testUnYUnaSolosSonArticulo() throws {
        XCTAssertEqual(try texto("una nave"), "una nave")
        XCTAssertEqual(try texto("treinta y una naves"), "31 naves")
        XCTAssertEqual(try texto("ciento un ciclos"), "101 ciclos")
    }

    func testYSueltaNoEsNumero() throws {
        XCTAssertEqual(try texto("paz y luz"), "paz y luz")
        XCTAssertEqual(try texto("treinta y paz"), "30 y paz")
    }

    func testNumerosQueNoSeCombinanQuedanSeparados() throws {
        XCTAssertEqual(try texto("dos tres"), "2 3")
    }

    func testCifrasNoCambian() throws {
        XCTAssertEqual(try texto("15 naves"), "15 naves")
        XCTAssertEqual(try texto("9.999 naves"), "9999 naves")
    }

    func testSinLexiconNoConvierte() {
        XCTAssertEqual(Normalizador().normalizar("quince").texto, "quince")
    }

    func testElNumeroTieneLaColumnaDeSuPrimeraPalabra() throws {
        let r = Normalizador(lexicon: try lexiconDeNumeros()).normalizar("¿Llegaron dos mil quince naves?")
        XCTAssertEqual(r.texto, "¿llegaron 2015 naves?")
        XCTAssertEqual(r.columnas.count, r.texto.count)
        XCTAssertEqual(r.columnaOriginal(11), 11, "el 2 viene de 'dos'")
        XCTAssertEqual(r.columnaOriginal(14), 11, "todo el número apunta a 'dos'")
        XCTAssertEqual(r.columnaOriginal(16), 26, "naves")
        XCTAssertEqual(r.columnaOriginal(21), 31, "?")
        XCTAssertEqual(r.columnaOriginal(22), 32)
    }

    // MARK: - Datos

    func testElArchivoSeCargaEnLaBD() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        let r = try bd.cargar(archivo: archivoDatos("numeros_es_v0.7.txt"))
        XCTAssertEqual(r.tipo, .vocabEs)
        XCTAssertEqual(r.nuevas, 61)
        XCTAssertTrue(r.errores.isEmpty)
        XCTAssertEqual(bd.entradasEspanol(forma: "dieciseis").first?.rasgos["v"], "16")
        XCTAssertTrue(bd.vocabularioEspanol().contains("quince"), "el corrector también los conoce")
    }

    func testInicializarCargaLosNumeros() throws {
        let bd = try BaseDatos(ruta: ":memory:")
        let cli = CLI(bd: bd, raizDatos: try raizRepo().appendingPathComponent("data"))
        let salida = cli.ejecutar(["inicializar"])
        XCTAssertTrue(salida.contains("Archivo: numeros_es_v0.7.txt"), salida)
        XCTAssertFalse(salida.contains("Error"), salida)
        XCTAssertEqual(Normalizador(lexicon: bd).normalizar("dos mil quince").texto, "2015")
    }
}
