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
        .executable(
            name: "demo",
            targets: ["demo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
        .package(url: "https://github.com/apple/swift-testing.git", revision: "e76a44f"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.4.0"),
        .package(url: "https://github.com/ringsaturn/cities-swift", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "geometry",
            path: "Sources/geometry"
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
            sources: ["tzf", "gen"],
            resources: [
                .copy("Resources/combined-with-oceans.reduce.preindex.pb"),
                .copy("Resources/combined-with-oceans.reduce.pb")
            ]
        ),
        .executableTarget(
            name: "demo",
            dependencies: ["tzf"],
            path: "Examples"
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
            name: "TimezoneFinderBenchmarks",
            dependencies: [
                "tzf",
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "Cities", package: "cities-swift")
            ],
            path: "Benchmarks/TimezoneFinderBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        ),
    ]
)