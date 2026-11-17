// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RehearsalSFTP",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "RehearsalSFTP", targets: ["RehearsalSFTP"])],
  dependencies: [
    .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.1"),
    // The SSH transport Citadel is built on (its fork); named here because the host key check uses its types.
    .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4"..<"0.4.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
  ],
  targets: [
    .target(
      name: "RehearsalSFTP",
      dependencies: [
        .product(name: "Citadel", package: "Citadel"),
        .product(name: "NIOSSH", package: "swift-nio-ssh"),
        .product(name: "NIOCore", package: "swift-nio"),
      ]),
    .testTarget(name: "RehearsalSFTPTests", dependencies: ["RehearsalSFTP"]),
  ]
)
