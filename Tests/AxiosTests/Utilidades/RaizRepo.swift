import Foundation

struct RaizRepoNoEncontrada: Error, CustomStringConvertible {
    var desde: String
    var description: String { "No se encontró Package.swift subiendo desde \(desde)" }
}

/// Raíz del repositorio: sube desde este archivo hasta encontrar Package.swift.
func raizRepo(desde archivo: String = #filePath) throws -> URL {
    var dir = URL(fileURLWithPath: archivo).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
        let padre = dir.deletingLastPathComponent()
        guard padre.path != dir.path else { throw RaizRepoNoEncontrada(desde: archivo) }
        dir = padre
    }
    return dir
}

/// URL de un archivo de `data/` en la raíz del repositorio.
func archivoDatos(_ nombre: String) throws -> URL {
    try raizRepo().appendingPathComponent("data").appendingPathComponent(nombre)
}
