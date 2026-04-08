# Getting Started

Quick start with tzf-swift.

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

    let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
    print("Beijing timezone:", timezone)

    let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
    print("Multiple possible timezones:", timezones)

    print("Data version:", finder.dataVersion())

    if let macauGeoJSON = finder.getTimezoneGeoJSON(timezoneName: "Asia/Macau") {
        print("Asia/Macau features:", macauGeoJSON.features.count)
        print(try macauGeoJSON.toJSONString(pretty: false))
    }
} catch {
    print("Error:", error)
    exit(1)
}
```

Output:

```txt
Build of product 'demo' complete! (0.14s)
Beijing timezone: Asia/Shanghai
Multiple possible timezones: ["Asia/Shanghai", "Asia/Urumqi"]
Data version: 2026a/2026a
Asia/Macau features: 1
{"features":[{"type":"Feature"...
```
