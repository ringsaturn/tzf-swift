# tzf-swift: a fast timezone finder for Swift

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fringsaturn%2Ftzf-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ringsaturn/tzf-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fringsaturn%2Ftzf-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ringsaturn/tzf-swift)
[![Swift](https://github.com/ringsaturn/tzf-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/ringsaturn/tzf-swift/actions/workflows/ci.yml)

> [!NOTE]
>
> This package use a simplified polygon data and not so accurate around borders.

## Usage

Add the dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/tzf-swift/tzf-swift.git", from: "0.2.0")
]
```

Then add something like this:

```swift
import Foundation
import tzf

do {
    let finder = try DefaultFinder()

    // Test for Beijing
    let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
    print("Beijing timezone:", timezone)

    // Test for a location with multiple possible timezones
    let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
    print("Multiple possible timezones:", timezones)

    // Get data version
    print("Data version:", finder.dataVersion())

} catch {
    print("Error:", error)
}
```

Output:

```
Build of product 'demo' complete! (0.15s)
Beijing timezone: Asia/Shanghai
Multiple possible timezones: ["Asia/Shanghai", "Asia/Urumqi"]
Data version: 2025a/2025a
```

## Performance

Just like tzf packages in Go/Rust/Python, the Swift version is also fast, and
designed for server-side high-performance use cases.

Hardware: MacBook Pro with Apple M3 Max.

It cost 4395ms to process 1 million queries. You can view full benchmark result
in [benchmark_baseline.txt](./benchmark_baseline.txt).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file
for details.

The data is licensed under [ODbL-1.0 license](./LICENSE_DATA), which compiled
from <https://github.com/evansiroky/timezone-boundary-builder>
