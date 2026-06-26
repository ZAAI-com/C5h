// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "C5hStore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "C5hStore", targets: ["C5hStore"])
    ],
    dependencies: [
        .package(path: "../C5hCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(
            name: "C5hStore",
            dependencies: [
                "C5hCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/C5hStore"
        ),
        .testTarget(
            name: "C5hStoreTests",
            dependencies: ["C5hStore", "C5hCore"],
            path: "Tests/C5hStoreTests"
        )
    ]
)
