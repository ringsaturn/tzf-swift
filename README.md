# tzf-swift: a fast timezone finder for Swift

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fringsaturn%2Ftzf-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ringsaturn/tzf-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fringsaturn%2Ftzf-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ringsaturn/tzf-swift)
[![Swift](https://github.com/ringsaturn/tzf-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/ringsaturn/tzf-swift/actions/workflows/ci.yml)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fringsaturn%2Ftzf-swift.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fringsaturn%2Ftzf-swift?ref=badge_shield)
![GitHub Tag](https://img.shields.io/github/v/tag/ringsaturn/tzf-swift)

> [!NOTE]
>
> This package ships simplified polygon data, so it is not entirely accurate
> around the border, but the error is small and bounded: every simplified
> boundary stays within ~111 m of the full-precision border. See
> [Accuracy](#accuracy) for measured numbers.

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

## Accuracy

tzf-swift bundles the topology-simplified dataset from [tzf-dist]:
`combined-with-oceans.topology.compress.topo.bin` (used by `Finder` and
`DefaultFinder`) and `combined-with-oceans.topology.preindex.bin` (used by
`PreindexFinder` and as `DefaultFinder`'s fast path). There is no
full-precision variant in the Swift package.

The Douglas-Peucker simplification uses an epsilon of 0.001 degrees, which caps
boundary displacement at roughly 111 m by construction. Measured against the
full-precision 2026c dataset with tzf's `internal/cmd/borderchange` (spherical
model, certified via Lipschitz interval subdivision):

| Metric                                            |                        Result |
| ------------------------------------------------- | ----------------------------: |
| Certified maximum boundary displacement           |    111.2 m (+1.0 m tolerance) |
| Boundary length displaced more than 100 m         |                         0.41% |
| Boundary length displaced more than 500 m         |                            0% |
| Total mis-assigned area                           | 16,828 km² (~0.003% of Earth) |
| Mis-assigned area within 100 m of the true border |                         92.8% |

In other words, only queries that land within ~111 m of a timezone border can
ever differ from the full-precision result, and most of that band is far
narrower. If your use case is sensitive inside that band, use the
full-precision finder in [`ringsaturn/tzf`][tzf] (Go) or
[`ringsaturn/tzf-rs`][tzf-rs] (Rust).

More details: [BORDER_CHANGE.md][border_change] in `ringsaturn/tzf`.

[tzf-dist]: https://github.com/ringsaturn/tzf-dist
[tzf]: https://github.com/ringsaturn/tzf
[tzf-rs]: https://github.com/ringsaturn/tzf-rs
[border_change]: https://github.com/ringsaturn/tzf/blob/main/BORDER_CHANGE.md

## Performance

Just like tzf packages in Go/Rust/Python, the Swift version is also fast, and
designed for server-side high-performance use cases.

Hardware: MacBook Pro with Apple M3 Max.

Benchmark Summary:

| Implementation                          | Test Scale | Execution Time (ms) | Success Rate | Operations per Second (op/sec) | Time per Op | Memory Usage (Peak MB) | Instructions |
| --------------------------------------- | ---------- | ------------------- | ------------ | ------------------------------ | ----------- | ---------------------- | ------------ |
| `TZF.DefaultFinder`                     | 1,000,000  | 435                 | 100%         | ~2,298,850                     | 435 ns      | 285                    | ~3.9 G       |
| `TZF.PreindexFinder`                    | 1,000,000  | 322                 | ~85%         | ~3,105,590                     | 322 ns      | 179                    | ~3.4 G       |
| `TZF.Finder`                            | 1,000,000  | 665                 | 100%         | ~1,503,759                     | 665 ns      | 268                    | ~5.7 G       |
| `LatLongToTimezone`                     | 100,000    | 17                  | 100%         | ~5,882,352                     | 170 ns      | 167                    | ~0.2 G       |
| `SwiftTimeZoneLookup.simple`            | 10,000     | 2,932               | 100%         | ~3,410                         | 293.2 μs    | 171                    | 37 G         |
| `SwiftTimeZoneLookup.lookup`            | 10,000     | 2,975               | 100%         | ~3,361                         | 297.5 μs    | 170                    | 37 G         |

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
