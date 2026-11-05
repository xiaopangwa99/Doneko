// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Doneko",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Doneko", targets: ["Doneko"])
    ],
    targets: [
        .executableTarget(
            name: "Doneko",
            path: "Sources/Doneko",
            exclude: [],
            resources: []
        )
    ]
)
