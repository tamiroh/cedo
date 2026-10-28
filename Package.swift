// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "cedo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "cedo", path: "Sources/cedo")
    ]
)
