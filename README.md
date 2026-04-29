# tzf-swift: a fast timezone finder for Swift

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fringsaturn%2Ftzf-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ringsaturn/tzf-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fringsaturn%2Ftzf-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ringsaturn/tzf-swift)
[![Swift](https://github.com/ringsaturn/tzf-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/ringsaturn/tzf-swift/actions/workflows/ci.yml)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fringsaturn%2Ftzf-swift.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fringsaturn%2Ftzf-swift?ref=badge_shield)
![GitHub Tag](https://img.shields.io/github/v/tag/ringsaturn/tzf-swift)

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

<!-- demo-main:start -->
```swift
import Foundation
import tzf

let finder = try DefaultFinder()

let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
print("Beijing timezone:", timezone)

let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
print("Multiple possible timezones:", timezones)

print("Data version:", finder.dataVersion())

if let macauGeoJSON = finder.getTimezoneGeoJSON(timezoneName: "Asia/Macau") {
  print("Asia/Macau features:", macauGeoJSON.features.count)
  print(try macauGeoJSON.toJSONString(pretty: false))
}
```
<!-- demo-main:end -->

Output:

<!-- demo-output:start -->
```txt
Beijing timezone: Asia/Shanghai
Multiple possible timezones: ["Asia/Shanghai", "Asia/Urumqi"]
Data version: 2026a/2026a
Asia/Macau features: 1
{"type":"FeatureCollection","features":[{"geometry":{"type":"MultiPolygon","coor...
```
<!-- demo-output:end -->

## Performance

Just like tzf packages in Go/Rust/Python, the Swift version is also fast, and
designed for server-side high-performance use cases.

Hardware: MacBook Pro with Apple M3 Max.

Processing 1 million queries took ~1,300ms. Benchmark Summary (2026a data):

| Implementation               | Test Scale | Execution Time (ms) | Success Rate | Operations per Second (op/sec) | Memory Usage (Peak MB) | Instructions (G) |
| ---------------------------- | ---------- | ------------------- | ------------ | ------------------------------ | ---------------------- | ---------------- |
| `TZF.DefaultFinder`          | 1,000,000  | 1,306               | 100%         | ~766,000                       | 284                    | 16               |
| `TZF.Finder`                 | 1,000,000  | 1,607               | 100%         | ~622,000                       | 269                    | 22               |
| `TZF.PreindexFinder`         | 1,000,000  | 946                 | ~85%         | ~1,057,000                     | 184                    | 12               |
| `SwiftTimeZoneLookup.lookup` | 10,000     | 3,279               | 100%         | ~3,050                         | 179                    | 44               |
| `SwiftTimeZoneLookup.simple` | 10,000     | 3,311               | 100%         | ~3,020                         | 179                    | 44               |

Full benchmark results can be viewed in [benchmark_baseline.txt](./benchmark_baseline.txt).

### Run Benchmarks

Benchmarks are isolated in the `Benchmarks` subpackage so the main package stays
compatible with Swift 6.0 while benchmark tooling can use newer SwiftPM
features.

```bash
make bench
# or:
cd Benchmarks && swift package benchmark --target TimezoneFinderBenchmarks
```

## Related Projects

See [Project tzf](https://project-tzf.ringsaturn.me/docs/getting-started/) for
more information.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file
for details.

The data is licensed under [ODbL-1.0 license](./LICENSE_DATA), which compiled
from <https://github.com/evansiroky/timezone-boundary-builder>

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fringsaturn%2Ftzf-swift.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fringsaturn%2Ftzf-swift?ref=badge_large)
