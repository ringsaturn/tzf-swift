import Cities
import Foundation
import Testing

@testable import tzf

// PreindexFinder Tests
@Test func validCoordinates() async throws {
  let finder = try! PreindexFinder()

  // Test for Beijing
  let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
  #expect(timezone == "Asia/Shanghai")

  // Test for multiple results
  let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
  #expect(timezones.count == 2)
}

@Test func invalidCoordinates() async throws {
  let finder = try! PreindexFinder()

  // Test invalid longitude
  #expect(throws: TZFError.invalidCoordinates) {
    try finder.getTimezone(lng: 181.0, lat: 0.0)
  }

  // Test invalid latitude
  #expect(throws: TZFError.invalidCoordinates) {
    try finder.getTimezone(lng: 0.0, lat: 91.0)
  }
}

@Test func dataVersion() async throws {
  // Load test data
  let finder = try! PreindexFinder()

  #expect(!finder.dataVersion().isEmpty)
}

// Finder Tests
@Test func finderValidCoordinates() async throws {
  // Load test data
  let finder = try! Finder()

  // Test for Beijing
  let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
  #expect(timezone == "Asia/Shanghai")

  // Test for multiple results
  let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
  #expect(!timezones.isEmpty)
}

@Test func finderInvalidCoordinates() async throws {
  // Load test data
  let finder = try! Finder()

  // Test invalid longitude
  #expect(throws: FinderError.noTimezoneFound) {
    try finder.getTimezone(lng: 181.0, lat: 0.0)
  }

  // Test invalid latitude
  #expect(throws: FinderError.noTimezoneFound) {
    try finder.getTimezone(lng: 0.0, lat: 91.0)
  }
}

@Test func finderDataVersion() async throws {
  // Load test data
  let finder = try! Finder()

  #expect(!finder.dataVersion().isEmpty)
}

@Test func finderEdgeCases() async throws {
  // Load test data
  let finder = try! Finder()

  // Test International Date Line
  let timezone1 = try finder.getTimezone(lng: 180.0, lat: 0.0)
  #expect(!timezone1.isEmpty)

  let timezone2 = try finder.getTimezone(lng: -180.0, lat: 0.0)
  #expect(!timezone2.isEmpty)

  let timezone3 = try finder.getTimezone(lng: 0.0, lat: -90.0)
  #expect(timezone3 == "Antarctica/McMurdo")

  let timezone4 = try finder.getTimezone(lng: 0.0, lat: 0.0)
  #expect(timezone4 == "Etc/GMT")

  let timezone5 = try finder.getTimezone(lng: 7.209253, lat: 53.242293)
  #expect(timezone5 == "Europe/Berlin")

  let timezone6 = try finder.getTimezone(lng: 7.207879, lat: 53.239692)
  #expect(timezone6 == "Europe/Amsterdam")
}

@Test func defaultFinderValidCoordinates() async throws {
  // Load test data
  let finder = try! DefaultFinder()

  // Test for Beijing
  let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
  #expect(timezone == "Asia/Shanghai")

  // Test for multiple results
  let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
  #expect(!timezones.isEmpty)
}

@Test func defaultFinderIterAllCities() async throws {
  // This test should only run with `swift test -c release` since only release
  // builds are optimized for performance.
  #if !DEBUG
    let cities = try Cities()
    let allCities = cities.getAllCities()
    #expect(allCities.count != 0)

    let randomCity = cities.getRandomCity()
    #expect(randomCity != nil)
    #expect(!randomCity!.name.isEmpty)

    let finder = try DefaultFinder()
    for city in allCities {
      let lng = Double(city.lng) ?? 0.0
      let lat = Double(city.lat) ?? 0.0
      let timezone = try finder.getTimezone(lng: lng, lat: lat)
      #expect(!timezone.isEmpty)
    }
  #else
    print("Skipping defaultFinderIterAllCities test in debug mode")
  #endif
}
