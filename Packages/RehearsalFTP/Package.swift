// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RehearsalFTP",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "RehearsalFTP", targets: ["RehearsalFTP"])],
  targets: [
    .target(name: "RehearsalFTP"),
    .testTarget(name: "RehearsalFTPTests", dependencies: ["RehearsalFTP"]),
  ]
)
