import Cities
import Foundation
import Testing

@testable import tzf

// MARK: - Known locations

private func assertKnownLocations(_ finder: any F) throws {
  #expect(try finder.getTimezone(lng: 116.3883, lat: 39.9289) == "Asia/Shanghai")
  #expect(try finder.getTimezone(lng: 121.3547, lat: 31.1139) == "Asia/Shanghai")
  #expect(try finder.getTimezone(lng: 111.8674, lat: 34.4200) == "Asia/Shanghai")
  #expect(try finder.getTimezone(lng: -97.8674, lat: 34.4200) == "America/Chicago")
  #expect(try finder.getTimezone(lng: 139.4382, lat: 36.4432) == "Asia/Tokyo")
  #expect(try finder.getTimezone(lng: 24.5212, lat: 50.2506) == "Europe/Kyiv")
  #expect(try finder.getTimezone(lng: -0.9671, lat: 52.0152) == "Europe/London")
  #expect(try finder.getTimezone(lng: -4.5706, lat: 46.2747) == "Etc/GMT")
  #expect(try finder.getTimezone(lng: -73.7729, lat: 38.3530) == "Etc/GMT+5")
  #expect(try finder.getTimezone(lng: 114.1594, lat: 22.3173) == "Asia/Hong_Kong")
  #expect(try finder.getTimezone(lng: 9.8198, lat: 27.5775) == "Africa/Tripoli")
  // Shenzhen, very close to the Hong Kong border (WGS-84).
  #expect(try finder.getTimezone(lng: 114.0617, lat: 22.5180) == "Asia/Shanghai")
  #expect(
    try finder.getTimezone(lng: 12.452_899_553_691_935, lat: 41.903_699_636_969_634)
      == "Europe/Vatican")
  // Locations that used to fall into simplification gaps.
  #expect(!(try finder.getTimezone(lng: 8.61280918, lat: 47.66097966)).isEmpty)
  #expect(!(try finder.getTimezone(lng: 8.61231565, lat: 47.66148548)).isEmpty)
}

@Test func defaultFinderSmoke() throws {
  let finder = try DefaultFinder()
  try assertKnownLocations(finder)
  #expect(finder.dataVersion() == "2026c")
  #expect(finder.timezoneNames().count == 444)
}

@Test func embeddedFinderSmoke() throws {
  let finder = try EmbeddedFinder()
  try assertKnownLocations(finder)
  #expect(finder.dataVersion() == "2026c")
  #expect(finder.timezoneNames().count == 444)
}

@Test func findersFromCallerOwnedBytes() throws {
  let data = try TZFDist.loadLiteTZB()
  let a = try DefaultFinder(tzb: data)
  let b = try EmbeddedFinder(tzb: data)
  #expect(try a.getTimezone(lng: 116.3883, lat: 39.9289) == "Asia/Shanghai")
  #expect(try b.getTimezone(lng: 116.3883, lat: 39.9289) == "Asia/Shanghai")
}

@Test func multipleTimezones() throws {
  let finder = try DefaultFinder()
  let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
  #expect(timezones == ["Asia/Shanghai", "Asia/Urumqi"])

  let embedded = try EmbeddedFinder()
  #expect(try embedded.getTimezones(lng: 87.5703, lat: 43.8146) == timezones)
}

// MARK: - Input domain

@Test func invalidCoordinatesAreRejected() throws {
  let finders: [any F] = [try DefaultFinder(), try EmbeddedFinder()]
  for finder in finders {
    for (lng, lat) in [
      (Double.nan, 39.9), (116.4, Double.nan), (Double.infinity, 0.0),
      (0.0, -Double.infinity), (-180.5, 0.0), (180.5, 0.0), (0.0, 90.5), (0.0, -90.5),
    ] {
      #expect(throws: TZFError.invalidCoordinates) {
        try finder.getTimezone(lng: lng, lat: lat)
      }
      #expect(throws: TZFError.invalidCoordinates) {
        try finder.getTimezones(lng: lng, lat: lat)
      }
    }
  }
}

@Test func edgeCases() throws {
  let finders: [any F] = [try DefaultFinder(), try EmbeddedFinder()]
  for finder in finders {
    #expect(!(try finder.getTimezone(lng: 180.0, lat: 0.0)).isEmpty)
    #expect(!(try finder.getTimezone(lng: -180.0, lat: 0.0)).isEmpty)
    #expect(try finder.getTimezone(lng: 0.0, lat: -90.0) == "Antarctica/McMurdo")
    #expect(try finder.getTimezone(lng: 0.0, lat: 0.0) == "Etc/GMT")
    #expect(try finder.getTimezone(lng: 7.209253, lat: 53.242293) == "Europe/Berlin")
    #expect(try finder.getTimezone(lng: 7.207879, lat: 53.239692) == "Europe/Amsterdam")
  }
}

// MARK: - Borders

/// A query landing exactly on a shared polygon border belongs to both
/// neighbours rather than to neither (tzf-rs #207).
@Test func nauticalBorderIsNotAGap() throws {
  let finders: [any F] = [try DefaultFinder(), try EmbeddedFinder()]
  for finder in finders {
    // The nautical zones are 15°-wide strips, so their borders sit on
    // whole meridians.
    for (lng, lat) in [(7.5, 54.5), (-22.5, 54.5)] {
      #expect(!(try finder.getTimezone(lng: lng, lat: lat)).isEmpty)
      #expect(try finder.getTimezones(lng: lng, lat: lat).count == 2)
    }
    #expect(try finder.getTimezones(lng: 7.5, lat: 54.5) == ["Etc/GMT", "Etc/GMT-1"])
    #expect(try finder.getTimezones(lng: -22.5, lat: 54.5) == ["Etc/GMT+1", "Etc/GMT+2"])

    #expect(try finder.getTimezone(lng: 7.4999, lat: 54.5) == "Etc/GMT")
    #expect(try finder.getTimezone(lng: 7.5001, lat: 54.5) == "Etc/GMT-1")
    #expect(try finder.getTimezone(lng: -22.4999, lat: 54.5) == "Etc/GMT+1")
    #expect(try finder.getTimezone(lng: -22.5001, lat: 54.5) == "Etc/GMT+2")
  }
}

/// A 1°×1° sweep of the whole globe: nothing may miss.
@Test func globalGridHasNoHoles() throws {
  let finder = try DefaultFinder()
  var empty: [(Double, Double)] = []
  var lng = -179.5
  while lng <= 179.5 {
    var lat = -89.5
    while lat <= 89.5 {
      if (try? finder.getTimezone(lng: lng, lat: lat)) == nil {
        empty.append((lng, lat))
      }
      lat += 1.0
    }
    lng += 1.0
  }
  #expect(empty.isEmpty, "\(empty.count) empty results, first few: \(empty.prefix(10))")
}

// MARK: - Mechanism parity

private func assertSame(_ a: any F, _ b: any F, lng: Double, lat: Double) {
  let na = try? a.getTimezone(lng: lng, lat: lat)
  let nb = try? b.getTimezone(lng: lng, lat: lat)
  #expect(na == nb, "getTimezone mismatch at (\(lng), \(lat))")
  let la = try? a.getTimezones(lng: lng, lat: lat)
  let lb = try? b.getTimezones(lng: lng, lat: lat)
  #expect(la == lb, "getTimezones mismatch at (\(lng), \(lat))")
}

@Test func parityMetadata() throws {
  let expanded = try DefaultFinder()
  let inplace = try EmbeddedFinder()
  #expect(expanded.dataVersion() == inplace.dataVersion())
  #expect(expanded.timezoneNames() == inplace.timezoneNames())
}

/// Exact whole-degree coordinates land on nautical-zone borders and grid
/// cell corners — the hardest inputs for boundary parity.
@Test func parityCoarseGridIncludingBorders() throws {
  let expanded = try DefaultFinder()
  let inplace = try EmbeddedFinder()
  var lng = -180.0
  while lng <= 180.0 {
    var lat = -90.0
    while lat <= 90.0 {
      assertSame(expanded, inplace, lng: lng, lat: lat)
      assertSame(expanded, inplace, lng: lng + 0.5, lat: lat + 0.5)
      lat += 3.0
    }
    lng += 3.0
  }
}

/// Every city, plus boundary-biased jitter where the two raycast paths would
/// disagree first if they disagree at all. Release builds only: debug PIP
/// over the whole city set is slow.
@Test func parityWorldCities() throws {
  #if !DEBUG
    let expanded = try DefaultFinder()
    let inplace = try EmbeddedFinder()
    let cities = try Cities().getAllCities()
    #expect(!cities.isEmpty)
    for (i, city) in cities.enumerated() {
      let lng = Double(city.lng) ?? 0.0
      let lat = Double(city.lat) ?? 0.0
      assertSame(expanded, inplace, lng: lng, lat: lat)
      #expect(!(try expanded.getTimezone(lng: lng, lat: lat)).isEmpty)
      if i % 7 == 0 {
        for (dx, dy) in [(0.01, 0.0), (-0.01, 0.0), (0.0, 0.01), (0.0, -0.01), (0.02, 0.02)] {
          assertSame(
            expanded, inplace,
            lng: min(max(lng + dx, -180.0), 180.0), lat: min(max(lat + dy, -90.0), 90.0))
        }
      }
    }
  #else
    print("Skipping parityWorldCities in debug mode")
  #endif
}

// MARK: - Malformed input

private func liteBytes() throws -> [UInt8] {
  [UInt8](try TZFDist.loadLiteTZB())
}

@Test func emptyAndTruncatedFilesAreRejected() throws {
  #expect(throws: TZFError.self) { try DefaultFinder(tzb: Data()) }
  #expect(throws: TZFError.self) { try EmbeddedFinder(tzb: Data()) }
  let data = try liteBytes()
  for len in [1, 4, 63, 64, 1024, data.count - 1] {
    #expect(throws: TZFError.self, "truncation to \(len) bytes accepted") {
      try EmbeddedFinder(tzb: Data(data[..<len]))
    }
  }
}

@Test func badMagicIsRejected() throws {
  var data = try liteBytes()
  data[0] = UInt8(ascii: "X")
  #expect(throws: TZFError.malformed("magic or format major")) {
    try EmbeddedFinder(tzb: Data(data))
  }
}

@Test func wrongFormatMajorIsRejected() throws {
  var data = try liteBytes()
  data[4] = 9
  #expect(throws: TZFError.self) { try EmbeddedFinder(tzb: Data(data)) }
}

@Test func unknownProfileIsRejected() throws {
  var data = try liteBytes()
  data[48] = 7
  #expect(throws: TZFError.self) { try EmbeddedFinder(tzb: Data(data)) }
}

@Test func corruptedPayloadFailsCRC() throws {
  var data = try liteBytes()
  data[data.count / 2] ^= 0xff
  #expect(throws: TZFError.malformed("CRC32")) { try DefaultFinder(tzb: Data(data)) }
}

@Test func mProfileFilesAreRejected() throws {
  // The profile byte is checked before the CRC, so flipping it exercises
  // that path.
  var data = try liteBytes()
  data[48] = 1
  #expect(throws: TZFError.unsupportedProfile) { try DefaultFinder(tzb: Data(data)) }
  #expect(throws: TZFError.unsupportedProfile) { try EmbeddedFinder(tzb: Data(data)) }
}

// MARK: - GeoJSON

@Test func timezoneGeoJSONExport() throws {
  let finders: [any F] = [try DefaultFinder(), try EmbeddedFinder()]
  for finder in finders {
    let collection = finder.getTimezoneGeoJSON(timezoneName: "Asia/Shanghai")
    #expect(collection?.type == "FeatureCollection")
    #expect(collection?.features.count == 1)
    #expect(collection?.features.first?.properties.tzid == "Asia/Shanghai")
    #expect(collection?.features.first?.geometry.type == "MultiPolygon")
    let ring = collection?.features.first?.geometry.coordinates.first?.first
    #expect((ring?.count ?? 0) >= 4)
    #expect(ring?.first == ring?.last, "GeoJSON rings must be closed")

    #expect(finder.getTimezoneGeoJSON(timezoneName: "Mars/Olympus_Mons") == nil)
  }
}

@Test func geoJSONEncoding() throws {
  let finder = try DefaultFinder()
  let collection = finder.toGeoJSON()
  #expect(collection.type == "FeatureCollection")
  #expect(collection.features.count == 444)

  let compact = try collection.toJSONString()
  #expect(compact.contains("\"type\":\"FeatureCollection\""))

  let pretty = try collection.toJSONString(pretty: true)
  #expect(pretty.contains("\n"))
}

/// The expanded and in-place export paths must produce identical geometry.
@Test func geoJSONMatchesBetweenFinders() throws {
  let expanded = try DefaultFinder()
  let inplace = try EmbeddedFinder()
  for name in ["Asia/Shanghai", "Asia/Macau", "Europe/Berlin", "America/Chicago"] {
    let a = expanded.getTimezoneGeoJSON(timezoneName: name)
    let b = inplace.getTimezoneGeoJSON(timezoneName: name)
    #expect(a != nil)
    #expect(a == b, "export mismatch for \(name)")
  }
}

@Test func preindexGeoJSONShape() throws {
  let finder = try DefaultFinder()
  let collection = try #require(finder.getTimezonePreindexGeoJSON(timezoneName: "Asia/Shanghai"))
  #expect(collection.type == "FeatureCollection")
  #expect(collection.features.count == 1)
  let feature = collection.features[0]
  #expect(feature.properties.tzid == "Asia/Shanghai")
  #expect(feature.geometry.type == "MultiPolygon")
  #expect(!feature.geometry.coordinates.isEmpty)

  // Every tile is a single closed 5-point rectangle ring.
  for polygon in feature.geometry.coordinates {
    #expect(polygon.count == 1, "tile polygons carry no holes")
    let ring = polygon[0]
    #expect(ring.count == 5)
    #expect(ring[0] == ring[4], "ring must be closed")
    #expect(ring[0][1] == ring[1][1], "bottom edge is horizontal")
    #expect(ring[1][0] == ring[2][0], "right edge is vertical")
  }

  // A point the preindex fast path answers must sit inside one tile bbox.
  let (lng, lat) = (116.3883, 39.9289)
  let covered = feature.geometry.coordinates.contains { polygon in
    let ring = polygon[0]
    return ring[0][0] <= lng && lng <= ring[2][0] && ring[0][1] <= lat && lat <= ring[2][1]
  }
  #expect(covered, "no preindex tile covers the Beijing sample point")

  #expect(finder.getTimezonePreindexGeoJSON(timezoneName: "Invalid/Timezone") == nil)
}

@Test func preindexGeoJSONMatchesBetweenFinders() throws {
  let expanded = try DefaultFinder()
  let inplace = try EmbeddedFinder()
  for name in ["Asia/Shanghai", "Europe/Berlin", "America/Chicago"] {
    let a = try #require(expanded.getTimezonePreindexGeoJSON(timezoneName: name))
    let b = try #require(inplace.getTimezonePreindexGeoJSON(timezoneName: name))
    #expect(a == b, "preindex export mismatch for \(name)")
  }
  let a = try #require(expanded.toPreindexGeoJSON())
  let b = try #require(inplace.toPreindexGeoJSON())
  #expect(!a.features.isEmpty)
  #expect(a == b)
}

// MARK: - Tile math

@Test func tileKeysMatchReference() throws {
  // deg2num(116.3883, 39.9289, 7) == (105, 48) in tzf-rs.
  let (x, y) = tileXY(lng: 116.3883, lat: 39.9289, zoom: 7)
  #expect(x == 105 && y == 48)
  let id = TileID(x: 105, y: 48, z: 7)
  #expect(id.xyz.x == 105 && id.xyz.y == 48 && id.xyz.z == 7)
  #expect(id.shift(2).xyz == (26, 12, 5))
  // Poles and the antimeridian must not trap.
  _ = tileXY(lng: 180.0, lat: 90.0, zoom: 12)
  _ = tileXY(lng: -180.0, lat: -90.0, zoom: 12)
  _ = tileXY(lng: 0.0, lat: 85.0511, zoom: 12)
  _ = tileXY(lng: 0.0, lat: -85.0511, zoom: 12)
}
