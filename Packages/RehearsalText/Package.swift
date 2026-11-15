// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RehearsalText",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RehearsalText", targets: ["RehearsalText"])],
    targets: [
        .target(name: "RehearsalText"),
        .testTarget(name: "RehearsalTextTests", dependencies: ["RehearsalText"]),
    ]
)
