// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Recall", path: "Sources/Recall")
    ]
)
