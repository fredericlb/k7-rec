// swift-tools-version:5.10
import PackageDescription

let package = Package(
  name: "RehearsalAudio",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "RehearsalAudio", targets: ["RehearsalAudio"])],
  targets: [
    .target(name: "RehearsalAudio"),
    .testTarget(name: "RehearsalAudioTests", dependencies: ["RehearsalAudio"]),
  ]
)
