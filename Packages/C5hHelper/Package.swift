// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "C5hHelper",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "C5hHelper", targets: ["C5hHelper"])
    ],
    dependencies: [
        .package(path: "../C5hCore"),
        .package(path: "../C5hStore")
    ],
    targets: [
        .executableTarget(
            name: "C5hHelper",
            dependencies: ["C5hCore", "C5hStore"],
            path: "Sources/C5hHelper"
        )
    ]
)
