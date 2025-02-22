# tzf-swift

## Usage

Add the dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/tzf-swift/tzf-swift.git", from: "0.1.0")
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
