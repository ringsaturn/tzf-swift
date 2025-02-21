// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tzf",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "tzf",
            targets: ["tzf"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
        .package(url: "https://github.com/jonblatho/PointInPolygon.git", from: "2.0.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "tzf"),
        .testTarget(
            name: "tzfTests",
            dependencies: ["tzf"]
        ),
    ]
)
