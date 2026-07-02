// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "djukebox_server",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
        .package(path: "../DJukeboxCommon")
    ],
    targets: [
        // system sqlite3 (ships in the macOS/iOS SDKs; libsqlite3-dev on Linux).
        // No external package / network fetch; nothing touches Package.resolved.
        .systemLibrary(name: "CSQLite"),
        .target(name: "App", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "DJukeboxCommon", package: "DJukeboxCommon"),
            "CSQLite"
        ]),
        .target(name: "Run", dependencies: ["App"]),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"),
            .product(name: "XCTVapor", package: "vapor"),
        ])
    ],
    swiftLanguageModes: [.v6]
)
