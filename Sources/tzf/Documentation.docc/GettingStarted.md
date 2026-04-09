# Getting Started

Quick start with tzf-swift.

Add the dependency to your `Package.swift` file:

![GitHub Tag](https://img.shields.io/github/v/tag/ringsaturn/tzf-swift)

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
