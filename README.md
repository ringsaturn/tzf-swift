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

// Low-memory alternative: query the .tzb bytes in place.
let embedded = try EmbeddedFinder()
print("Embedded finder:", try embedded.getTimezone(lng: 139.6917, lat: 35.6895))
```
<!-- demo-main:end -->

Output:

<!-- demo-output:start -->
```txt
Beijing timezone: Asia/Shanghai
Multiple possible timezones: ["Asia/Shanghai", "Asia/Urumqi"]
Data version: 2026c
Asia/Macau features: 1
{"features":[{"geometry":{"coordinates":[[[[113.54701,22.13804],[113.54703,22.13...
Embedded finder: Asia/Tokyo
```
<!-- demo-output:end -->

## Finders

Since v2 the package is protobuf-free: the data source is the TZF embedded
binary format (`.tzb`) shipped by [tzf-dist], and two finder types consume it.
Both conform to the `F` protocol and return identical results over the same
file.

| Finder           | Mechanism                                                                | Load   | Resident memory | `getTimezone` | `getTimezones` |
| ---------------- | ------------------------------------------------------------------------ | -----: | --------------: | ------------: | -------------: |
| `DefaultFinder`  | expands `lite.tzb` into int32 polygons at load; FUZZY preindex fast path | ~16 ms |          ~48 MB |       ~205 ns |        ~455 ns |
| `EmbeddedFinder` | queries the `lite.tzb` bytes in place, no geometry expansion             |  ~2 ms |          ~10 MB |       ~570 ns |        ~2.5 µs |

Query latencies are per-call means over the world-cities dataset in sequential
order (Apple M3 Max, `2026c`); see [Performance](#performance) for the
benchmark-harness numbers.

- `getTimezone` is fuzzy-first: a preindex tile resolves most queries with no
  point-in-polygon work.
- `getTimezones` runs the polygon scan in every finder and is the call to use
  when a point can belong to more than one timezone. Results are sorted
  lexicographically, and a point exactly on a shared border belongs to every
  touching timezone.
- Both finders accept caller-owned bytes through `init(tzb:)`, so tzf-dist's
  full-precision `full.tzb` (~14 MB, not bundled) can be loaded the same way:

```swift
let full = try DefaultFinder(tzb: try Data(contentsOf: URL(fileURLWithPath: "full.tzb")))
```

`.tzm` memory images are Go-only and are rejected with
`TZFError.unsupportedProfile`.

### Migrating from v1

| v1                                    | v2                                                                  |
| ------------------------------------- | ------------------------------------------------------------------- |
| `DefaultFinder()`                     | unchanged; now backed by `lite.tzb`                                  |
| `Finder()`                            | `DefaultFinder()` (polygon-exact queries via `getTimezones`)         |
| `PreindexFinder()`                    | removed; the preindex is the fast path inside every finder           |
| `FinderError.noTimezoneFound`         | `TZFError.noTimezoneFound`                                          |
| `dataVersion()` → `"2026a/2026a"`     | one dataset version, e.g. `"2026c"`                                 |
| `getTimezones` order                  | now sorted lexicographically                                        |
| preindex tile GeoJSON on `PreindexFinder` | `toPreindexGeoJSON()` / `getTimezonePreindexGeoJSON(timezoneName:)` on every finder |

## Accuracy

tzf-swift bundles the topology-simplified dataset from [tzf-dist]
(`lite.tzb`). There is no full-precision variant in the Swift package, but
`full.tzb` from a tzf-dist release loads through `init(tzb:)` (see above).

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
narrower. If your use case is sensitive inside that band, load `full.tzb`, or
use [`ringsaturn/tzf`][tzf] (Go) or [`ringsaturn/tzf-rs`][tzf-rs] (Rust).

More details: [BORDER_CHANGE.md][border_change] in `ringsaturn/tzf`.

[tzf-dist]: https://github.com/ringsaturn/tzf-dist
[tzf]: https://github.com/ringsaturn/tzf
[tzf-rs]: https://github.com/ringsaturn/tzf-rs
[border_change]: https://github.com/ringsaturn/tzf/blob/main/BORDER_CHANGE.md

## Performance

Just like tzf packages in Go/Rust/Python, the Swift version is also fast, and
designed for server-side high-performance use cases.

Hardware: MacBook Pro with Apple M3 Max. The throughput rows include the
harness's own per-iteration cost (a random city draw plus string-to-double
parsing, ~160 ns); `(init)` rows build one finder from the bundled `lite.tzb`.

Benchmark Summary:

| Implementation                          | Test Scale | Execution Time (ms) | Success Rate | Operations per Second (op/sec) | Time per Op | Memory Usage (Peak MB) | Instructions |
| --------------------------------------- | ---------- | ------------------- | ------------ | ------------------------------ | ----------- | ---------------------- | ------------ |
| `TZF.DefaultFinder`                     | 1,000,000  | 543                 | 100%         | ~1,841,620                     | 543 ns      | 203                    | ~3.9 G       |
| `TZF.DefaultFinder.getTimezones`        | 1,000,000  | 1,320               | 100%         | ~757,575                       | 1.3 μs      | 203                    | 12 G         |
| `TZF.EmbeddedFinder`                    | 1,000,000  | 1,186               | 100%         | ~843,170                       | 1.2 μs      | 169                    | 12 G         |
| `TZF.DefaultFinder (init)`              | per load   | 16.000              | 100%         | ~62                            | 16.0 ms     | 77                     | ~0.4 G       |
| `TZF.EmbeddedFinder (init)`             | per load   | 2.085               | 100%         | ~479                           | 2.1 ms      | 24                     | ~0.0 G       |
| `LatLongToTimezone`                     | 100,000    | 20                  | 100%         | ~5,000,000                     | 200 ns      | 168                    | ~0.2 G       |
| `SwiftTimeZoneLookup.simple`            | 10,000     | 3,047               | 100%         | ~3,281                         | 304.7 μs    | 172                    | 37 G         |
| `SwiftTimeZoneLookup.lookup`            | 10,000     | 3,026               | 100%         | ~3,304                         | 302.6 μs    | 172                    | 37 G         |

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
