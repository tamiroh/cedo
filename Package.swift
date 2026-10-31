// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cedo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cedo", targets: ["CedoApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.19.0")
    ],
    targets: [
        .executableTarget(
            name: "CedoApp",
            dependencies: ["CedoKit", "SwiftTerm"],
            path: "Sources/CedoApp"
        ),
        .target(
            name: "CedoKit",
            path: "Sources/CedoKit"
        ),
        .testTarget(
            name: "CedoKitTests",
            dependencies: ["CedoKit"],
            path: "Tests/CedoKitTests"
        ),
    ]
)
