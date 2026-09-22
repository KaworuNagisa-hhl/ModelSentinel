// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelSentinel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ModelSentinel", targets: ["ModelSentinel"])
    ],
    targets: [
        .executableTarget(
            name: "ModelSentinel",
            path: "Sources/ModelSentinel"
        )
    ]
)
