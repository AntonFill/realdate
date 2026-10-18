// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "realdate",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.

        // Reads the command line the way getopt does. A module of its own, so it cannot reach
        // into realdate's code and can move into a package once a second tool uses it.
        .target(
            name: "CommandLineOptions"
        ),
        .executableTarget(
            name: "realdate",
            dependencies: [
                "CommandLineOptions"
            ]
        ),
        .testTarget(
            name: "CommandLineOptionsTests",
            dependencies: [
                "CommandLineOptions"
            ]
        ),
        .testTarget(
            name: "realdateTests",
            dependencies: [
                "realdate"
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
