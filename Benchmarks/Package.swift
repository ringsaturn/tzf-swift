// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "tzf-benchmarks",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  dependencies: [
    .package(path: ".."),
    .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.30.0", traits: []),
    .package(url: "https://github.com/ringsaturn/cities-swift.git", from: "0.1.1"),
    .package(url: "https://github.com/patrick-zippenfenig/SwiftTimeZoneLookup.git", from: "1.0.7"),
    .package(url: "https://github.com/drtimcooper/LatLongToTimezone.git", from: "1.1.3"),
  ],
  targets: [
    .executableTarget(
      name: "TimezoneFinderBenchmarks",
      dependencies: [
        .product(name: "tzf", package: "tzf-swift"),
        .product(name: "Benchmark", package: "package-benchmark"),
        .product(name: "Cities", package: "cities-swift"),
        .product(name: "SwiftTimeZoneLookup", package: "SwiftTimeZoneLookup"),
        .product(name: "LatLongToTimezone", package: "LatLongToTimezone"),
      ],
      path: "TimezoneFinderBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ]
)
