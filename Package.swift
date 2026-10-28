// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "cedo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.19.0")
    ],
    targets: [
        .executableTarget(
            name: "cedo",
            dependencies: ["SwiftTerm"],
            path: "Sources/cedo"
        )
    ]
)
