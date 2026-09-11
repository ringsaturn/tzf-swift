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
