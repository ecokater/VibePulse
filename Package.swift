// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibePulse",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VibePulse", targets: ["VibePulse"])
    ],
    targets: [
        .executableTarget(
            name: "VibePulse",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
