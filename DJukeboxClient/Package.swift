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
        .target(
            name: "DJukeboxClient",
            dependencies: ["DJukeboxCommon"],
            path: "Sources"),
    ]
)
