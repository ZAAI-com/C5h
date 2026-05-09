// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IconForge",
    platforms: [.macOS("13.0")],
    targets: [
        .executableTarget(
            name: "IconForge",
            path: "Sources/IconForge"
        )
    ]
)
