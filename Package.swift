// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "cedo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cedo", targets: ["CedoApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.2"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
    ],
    targets: [
        .executableTarget(
            name: "CedoApp",
            dependencies: ["CedoUI"]
        ),
        .target(
            name: "CedoUI",
            dependencies: ["CedoHistory", "CedoKit", "CedoSupport", "SwiftTerm"]
        ),
        .target(
            name: "CedoKit",
            dependencies: ["CedoSupport"],
            path: "Sources/CedoKit"
        ),
        .target(name: "CedoSupport"),
        .target(name: "CedoHistory", dependencies: ["CedoSupport"]),
        .testTarget(name: "CedoHistoryTests", dependencies: ["CedoHistory", "CedoSupport"]),
        .testTarget(
            name: "CedoKitTests",
            dependencies: ["CedoKit"],
            path: "Tests/CedoKitTests"
        ),
        .testTarget(
            name: "CedoUITests",
            dependencies: ["CedoUI", "CedoKit"],
            path: "Tests/CedoUITests"
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
