// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RehearsalAudio",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "RehearsalAudio", targets: ["RehearsalAudio"])],
  targets: [
    // Signalsmith Stretch (MIT, vendored in Sources/CStretch/vendor) behind a C face; its FFTs run on Accelerate.
    .target(
      name: "CStretch",
      exclude: ["vendor/LICENSE-signalsmith-stretch.txt", "vendor/LICENSE-signalsmith-linear.txt", "vendor/VERSIONS.txt"],
      cxxSettings: [.define("SIGNALSMITH_USE_ACCELERATE"), .unsafeFlags(["-O3"])],
      linkerSettings: [.linkedFramework("Accelerate")]),
    .target(name: "RehearsalAudio", dependencies: ["CStretch"]),
    .testTarget(name: "RehearsalAudioTests", dependencies: ["RehearsalAudio"]),
  ],
  cxxLanguageStandard: .cxx17
)
