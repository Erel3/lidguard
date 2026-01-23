// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "LidGuard",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0")
  ],
  targets: [
    .executableTarget(
      name: "LidGuard",
      dependencies: ["SkyLightWindow"],
      path: "Sources"
    )
  ]
)
