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
    .package(url: "https://github.com/ringsaturn/tzf-swift.git", from: "{latest_version}")
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

Processing 1 million queries took 4500ms. Benchmark Summary:

| Implementation               | Test Scale | Execution Time (ms) | Success Rate | Operations per Second (op/sec) | Memory Usage (Peak MB) | Instructions (G) |
| ---------------------------- | ---------- | ------------------- | ------------ | ------------------------------ | ---------------------- | ---------------- |
| `TZF.DefaultFinder`          | 1,000,000  | 4,717               | 100%         | ~212,000                       | 129                    | 73               |
| `TZF.Finder`                 | 1,000,000  | 19,000              | 100%         | ~52,632                        | 115                    | 324              |
| `TZF.PreindexFinder`         | 1,000,000  | 1,548               | ~85%         | ~646,000                       | 129                    | 23               |
| `SwiftTimeZoneLookup.lookup` | 10,000     | 3,077               | 100%         | ~3,250                         | 105                    | 42               |
| `SwiftTimeZoneLookup.simple` | 10,000     | 3,209               | 100%         | ~3,116                         | 104                    | 45               |

Full benchmark results can be viewed in [benchmark_baseline.txt](./benchmark_baseline.txt).

## Related Projects

| Language or Sever         | Link                                                                    | Note                |
| ------------------------- | ----------------------------------------------------------------------- | ------------------- |
| Go                        | [`ringsaturn/tzf`](https://github.com/ringsaturn/tzf)                   |                     |
| Ruby                      | [`HarlemSquirrel/tzf-rb`](https://github.com/HarlemSquirrel/tzf-rb)     | build with tzf-rs   |
| Rust                      | [`ringsaturn/tzf-rs`](https://github.com/ringsaturn/tzf-rs)             |                     |
| Swift                     | [`ringsaturn/tzf-swift`](https://github.com/ringsaturn/tzf-swift)       |                     |
| Python                    | [`ringsaturn/tzfpy`](https://github.com/ringsaturn/tzfpy)               | build with tzf-rs   |
| HTTP API                  | [`ringsaturn/tzf-server`](https://github.com/ringsaturn/tzf-server)     | build with tzf      |
| HTTP API                  | [`racemap/rust-tz-service`](https://github.com/racemap/rust-tz-service) | build with tzf-rs   |
| Redis Server              | [`ringsaturn/tzf-server`](https://github.com/ringsaturn/tzf-server)     | build with tzf      |
| Redis Server              | [`ringsaturn/redizone`](https://github.com/ringsaturn/redizone)         | build with tzf-rs   |
| JS via Wasm(browser only) | [`ringsaturn/tzf-wasm`](https://github.com/ringsaturn/tzf-wasm)         | build with tzf-rs   |
| Online                    | [`ringsaturn/tzf-web`](https://github.com/ringsaturn/tzf-web)           | build with tzf-wasm |

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file
for details.

The data is licensed under [ODbL-1.0 license](./LICENSE_DATA), which compiled
from <https://github.com/evansiroky/timezone-boundary-builder>
