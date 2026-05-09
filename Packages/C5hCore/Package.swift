// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "C5hCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "C5hCore", targets: ["C5hCore"])
    ],
    targets: [
        .target(
            name: "C5hCore",
            path: "Sources/C5hCore"
        ),
        .testTarget(
            name: "C5hCoreTests",
            dependencies: ["C5hCore"],
            path: "Tests/C5hCoreTests"
        )
    ]
)
