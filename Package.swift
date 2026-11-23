// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Lumen", path: "Sources/Lumen")
    ]
)
