// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixelRotator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PixelRotator", targets: ["PixelRotator"])
    ],
    targets: [
        .target(name: "PixelRotatorCore"),
        .executableTarget(
            name: "PixelRotator",
            dependencies: ["PixelRotatorCore"]
        ),
        .executableTarget(
            name: "PixelRotatorCheck",
            dependencies: ["PixelRotatorCore"]
        ),
    ]
)
