// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tzf",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "tzf",
            targets: ["tzf"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.29.0"),
        .package(url: "https://github.com/apple/swift-testing.git", revision: "e76a44f"),
        .package(url: "https://github.com/ringsaturn/cities-swift.git", from: "0.1.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
    ],
    targets: [
        .target(
            name: "geometry",
            path: "Geometry"
        ),
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "tzf",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "geometry"
            ],
            path: "Sources",
            resources: [
                .copy("Resources/combined-with-oceans.reduce.preindex.bin"),
                .copy("Resources/combined-with-oceans.reduce.bin")
            ]
        ),
        .testTarget(
            name: "tzfTests",
            dependencies: [
                "tzf",
                .product(name: "Testing", package: "swift-testing"),
                .product(name: "Cities", package: "cities-swift")
            ]
        ),
        .executableTarget(
            name: "demo",
            dependencies: [
                "tzf",
            ],
            path: "Examples/Demo"
        ),
    ]
)
