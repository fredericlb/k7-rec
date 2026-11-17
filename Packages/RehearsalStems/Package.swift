// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RehearsalStems",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "RehearsalStems", targets: ["RehearsalStems"])],
  dependencies: [.package(path: "../RehearsalAudio")],
  targets: [
    .target(name: "RehearsalStems", dependencies: ["RehearsalAudio"]),
    .testTarget(name: "RehearsalStemsTests", dependencies: ["RehearsalStems"]),
  ]
)
