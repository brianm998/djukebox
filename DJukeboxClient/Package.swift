// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "DJukeboxClient",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "DJukeboxClient",
            targets: ["DJukeboxClient"]),
    ],
    dependencies: [
        .package(path: "../DJukeboxCommon"),
    ],
    targets: [
        // system sqlite3 (ships in the macOS/iOS SDKs; no external package).
        // Lives outside Sources/ because the DJukeboxClient target claims the
        // whole Sources/ directory.
        .systemLibrary(name: "CSQLite", path: "CSQLite"),
        .target(
            name: "DJukeboxClient",
            dependencies: ["DJukeboxCommon", "CSQLite"],
            path: "Sources"),
    ]
)
