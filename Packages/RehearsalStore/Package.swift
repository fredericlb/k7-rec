// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RehearsalStore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RehearsalStore", targets: ["RehearsalStore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.12.0"),
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "RehearsalStore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), "Yams"]
        ),
        .testTarget(name: "RehearsalStoreTests", dependencies: ["RehearsalStore"]),
    ]
)
