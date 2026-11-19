// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AxiosSwift",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "axios", targets: ["axios"]),
    ],
    targets: [
        // SQLite amalgamation (sqlite.org) compilada como target C para que
        // macOS, Windows y Linux usen exactamente la misma versión.
        .target(
            name: "CSQLite",
            cSettings: [
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
            ]
        ),
        .target(
            name: "AxiosCore",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "axios",
            dependencies: ["AxiosCore"]
        ),
        .testTarget(
            name: "AxiosTests",
            dependencies: ["AxiosCore", "CSQLite"]
        ),
    ]
)
