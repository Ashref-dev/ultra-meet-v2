// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UltraTranscribe",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UltraTranscribe", targets: ["UltraTranscribe"])],
    targets: [
        .executableTarget(name: "UltraTranscribe", path: "Sources", resources: [.copy("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "UltraTranscribeTests", dependencies: ["UltraTranscribe"], path: "Tests")
    ]
)
