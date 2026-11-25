import Foundation
import AxiosCore

let directorioActual = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

// Ruta de la BD: AXIOS_DB o "axios.db" en el directorio actual.
let rutaBD: String
if let variable = ProcessInfo.processInfo.environment["AXIOS_DB"], !variable.isEmpty {
    rutaBD = variable
} else {
    rutaBD = directorioActual.appendingPathComponent("axios.db")
        .withUnsafeFileSystemRepresentation { String(cString: $0!) }
}

let bd: BaseDatos
do {
    bd = try BaseDatos(ruta: rutaBD)
} catch {
    let detalle: String
    switch error {
    case ErrorBD.apertura(let m), ErrorBD.sql(let m), ErrorBD.esquema(let m): detalle = m
    default: detalle = "\(error)"
    }
    FileHandle.standardError.write(Data("No se pudo abrir la base de datos en \(rutaBD): \(detalle)\n".utf8))
    exit(1)
}

// El pipeline tiene la misma firma que CLI.Traductor. No registra nada: la CLI
// guarda cada pregunta una sola vez, también cuando el pipeline no pudo traducirla.
let cli = CLI(
    bd: bd, traductor: Pipeline.traducir,
    raizDatos: directorioActual.appendingPathComponent("data", isDirectory: true)
)
print(cli.ejecutar(Array(CommandLine.arguments.dropFirst())))
