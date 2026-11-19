import Foundation

struct RaizRepoNoEncontrada: Error, CustomStringConvertible {
    var desde: String
    var description: String { "No se encontró Package.swift subiendo desde \(desde)" }
}

/// Raíz del repositorio: sube desde este archivo hasta encontrar Package.swift.
/// Se comprueba la existencia con la URL (no con un String armado a mano) para que
/// funcione igual con rutas de Windows, y el ascenso tiene un límite por si la raíz
/// del disco no cambia al quitar el último componente.
func raizRepo(desde archivo: String = #filePath) throws -> URL {
    var dir = URL(fileURLWithPath: archivo).deletingLastPathComponent()
    for _ in 0..<64 {
        if (try? dir.appendingPathComponent("Package.swift").checkResourceIsReachable()) == true {
            return dir
        }
        let padre = dir.deletingLastPathComponent()
        if padre.standardizedFileURL == dir.standardizedFileURL { break }
        dir = padre
    }
    throw RaizRepoNoEncontrada(desde: archivo)
}

/// URL de un archivo de `data/` en la raíz del repositorio.
func archivoDatos(_ nombre: String) throws -> URL {
    try raizRepo().appendingPathComponent("data").appendingPathComponent(nombre)
}

/// Ruta del sistema de archivos de una URL, como la escribiría un usuario en la CLI.
/// En Windows `url.path` puede empezar con "/C:/..."; la representación del sistema
/// de archivos da la ruta nativa en los tres sistemas operativos.
func rutaSistema(_ url: URL) -> String {
    url.withUnsafeFileSystemRepresentation { String(cString: $0!) }
}
