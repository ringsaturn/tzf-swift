import Foundation
import SwiftProtobuf
import geometry

public typealias GeoJSONPolygonCoordinates = [[[Double]]]
public typealias GeoJSONMultiPolygonCoordinates = [GeoJSONPolygonCoordinates]

/// GeoJSON geometry for timezone boundaries.
public struct GeoJSONGeometry: Codable {
  public let type: String
  public let coordinates: GeoJSONMultiPolygonCoordinates

  public init(type: String, coordinates: GeoJSONMultiPolygonCoordinates) {
    self.type = type
    self.coordinates = coordinates
  }
}

/// GeoJSON properties that carry timezone name.
public struct GeoJSONProperties: Codable {
  public let tzid: String

  public init(tzid: String) {
    self.tzid = tzid
  }
}

/// GeoJSON feature for one timezone.
public struct GeoJSONFeature: Codable {
  public let type: String
  public let properties: GeoJSONProperties
  public let geometry: GeoJSONGeometry

  public init(type: String, properties: GeoJSONProperties, geometry: GeoJSONGeometry) {
    self.type = type
    self.properties = properties
    self.geometry = geometry
  }
}

/// GeoJSON feature collection for timezone boundaries.
public struct GeoJSONFeatureCollection: Codable {
  public let type: String
  public let features: [GeoJSONFeature]

  public init(type: String, features: [GeoJSONFeature]) {
    self.type = type
    self.features = features
  }

  public func toJSONString(pretty: Bool = false) throws -> String {
    let encoder = JSONEncoder()
    if pretty {
      encoder.outputFormatting = [.prettyPrinted]
    }
    let data = try encoder.encode(self)
    guard let output = String(data: data, encoding: .utf8) else {
      throw TZFError.dataError
    }
    return output
  }
}

/// A protocol defining the interface for timezone finders.
/// All timezone finder implementations must conform to this protocol.
public protocol F {
  /// Returns the version of the timezone data being used.
  ///
  /// - Returns: A string representing the data version.
  func dataVersion() -> String

  /// Returns the timezone for a given geographic coordinate.
  ///
  /// - Parameters:
  ///   - lng: The longitude coordinate in decimal degrees (-180 to 180)
  ///   - lat: The latitude coordinate in decimal degrees (-90 to 90)
  /// - Returns: The IANA timezone identifier as a string
  /// - Throws: An error if no timezone is found or if coordinates are invalid
  func getTimezone(lng: Double, lat: Double) throws -> String

  /// Returns all possible timezones for a given geographic coordinate.
  /// This is useful for locations near timezone boundaries where multiple
  /// timezones might be applicable.
  ///
  /// - Parameters:
  ///   - lng: The longitude coordinate in decimal degrees (-180 to 180)
  ///   - lat: The latitude coordinate in decimal degrees (-90 to 90)
  /// - Returns: An array of IANA timezone identifiers
  /// - Throws: An error if no timezone is found or if coordinates are invalid
  func getTimezones(lng: Double, lat: Double) throws -> [String]

  /// Convert all timezone boundaries to GeoJSON FeatureCollection.
  func toGeoJSON() -> GeoJSONFeatureCollection

  /// Convert one timezone boundary set to GeoJSON FeatureCollection.
  ///
  /// - Parameter timezoneName: IANA timezone name, for example "Asia/Tokyo"
  /// - Returns: GeoJSON collection if found, otherwise nil.
  func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection?
}

// MARK: - Polyline decode

/// Decodes a Google Maps Encoded Polyline byte sequence into geometry Points.
/// The encoding stores [lng, lat] pairs as delta-encoded zigzag integers with scale 1e5.
private func decodePolylineBytes(_ data: Data) -> [Point] {
  var results: [Point] = []
  let bytes = [UInt8](data)
  var i = 0

  func decodeSignedInt() -> Int? {
    var u: UInt = 0
    var shift: UInt = 0
    while i < bytes.count {
      let b = bytes[i]
      i += 1
      if b >= 95 {
        // continuation chunk (bits 5..9 of current group)
        u += UInt(b - 95) << shift
        shift += 5
      } else if b >= 63 {
        // terminal chunk
        u += UInt(b - 63) << shift
        // zigzag decode: even -> positive, odd -> negative
        if u & 1 == 0 {
          return Int(bitPattern: u >> 1)
        } else {
          return ~Int(bitPattern: u >> 1)
        }
      } else {
        return nil
      }
    }
    return nil
  }

  var prevLng: Int = 0
  var prevLat: Int = 0

  while i < bytes.count {
    guard let dLng = decodeSignedInt(), let dLat = decodeSignedInt() else { break }
    prevLng += dLng
    prevLat += dLat
    results.append(Point(x: Double(prevLng) / 1e5, y: Double(prevLat) / 1e5))
  }

  return results
}

// MARK: - Compressed ring expansion

/// Expands a sequence of CompressedRingSegments into a flat Point array by resolving
/// edge_forward / edge_reversed references against the pre-decoded shared edge table.
private func expandCompressedRing(
  _ segs: [Tzf_V1_CompressedRingSegment], edges: [[Point]]
) -> [Point] {
  var pts: [Point] = []
  for seg in segs {
    switch seg.content {
    case .inline(let inline):
      pts.append(contentsOf: decodePolylineBytes(inline.points))
    case .edgeForward(let idx):
      let edge = edges[Int(idx)]
      pts.append(contentsOf: edge)
    case .edgeReversed(let idx):
      let edge = edges[Int(idx)]
      pts.append(contentsOf: edge.reversed())
    case nil:
      break
    }
  }
  return pts
}

// MARK: - PreindexFinder

/// A high-performance timezone finder that uses pre-indexed map tiles for lookups.
///
/// PreindexFinder uses a tile-based approach (similar to web map tiles) to quickly
/// determine which timezone(s) a given coordinate belongs to. The data is pre-processed
/// and stored in a binary format for efficient lookup.
///
/// The finder iterates through zoom levels from `aggZoom` to `idxZoom`:
/// - Starting from the lowest zoom level (`aggZoom`), it checks if the coordinate falls within a tile
/// - If no timezone is found, it progressively increases the zoom level up to `idxZoom`
/// - Higher zoom levels provide more precise boundaries but require more tiles to be checked
/// - The process stops as soon as a timezone is found at any zoom level
///
/// This approach balances accuracy and performance by:
/// 1. Using coarser tiles first for quick matches
/// 2. Only moving to more detailed tiles when necessary
/// 3. Caching tile data for faster repeated lookups
public class PreindexFinder: F {
  private let preindexData: Tzf_V1_PreindexTimezones
  private let idxZoom: Int32
  private let aggZoom: Int32
  // One dictionary instead of two: halves hash lookups per zoom level.
  // Value ≥ 0 → single timezone index into tzNames.
  // Value < 0 → -(spanIdx+1), spanIdx indexes multiSpans for (start,count) into multiStore.
  private let tileData: [Int64: Int32]
  private let multiSpans: [(start: Int32, count: Int32)]
  private let tzNames: [String]
  private let multiStore: [Int32]

  public init() throws {
    let bundle = Bundle.module

    guard
      let preindexURL = bundle.url(
        forResource: "combined-with-oceans.topology.preindex", withExtension: "bin")
    else {
      throw TZFError.dataError
    }

    let preindexDataBytes = try Data(contentsOf: preindexURL)
    preindexData = try Tzf_V1_PreindexTimezones(serializedBytes: preindexDataBytes)
    idxZoom = preindexData.idxZoom
    aggZoom = preindexData.aggZoom

    // Build name index.
    var nameIndex = [String: Int32]()
    var namesArr = [String]()
    for key in preindexData.keys {
      if nameIndex[key.name] == nil {
        nameIndex[key.name] = Int32(namesArr.count)
        namesArr.append(key.name)
      }
    }

    // Group name indices by tile key, then sort alphabetically within each tile.
    // Key encoding: zoom(4bit) | x(13bit) | y(13bit) packed into Int64.
    var rawCache = [Int64: [Int32]]()
    for key in preindexData.keys {
      let tileKey = Int64(key.z) << 26 | Int64(key.x) << 13 | Int64(key.y)
      rawCache[tileKey, default: []].append(nameIndex[key.name]!)
    }
    for k in rawCache.keys { rawCache[k]?.sort { namesArr[Int($0)] < namesArr[Int($1)] } }

    // Build single combined dictionary: one lookup per zoom level instead of two.
    // Single-tz tiles: value = nameIdx (≥ 0).
    // Multi-tz tiles:  value = -(spanIdx+1) (< 0); spanIdx indexes multiSpansArr.
    var data = [Int64: Int32]()
    var spansArr = [(start: Int32, count: Int32)]()
    var store = [Int32]()
    data.reserveCapacity(rawCache.count)
    for (tileKey, idxs) in rawCache {
      if idxs.count == 1 {
        data[tileKey] = idxs[0]
      } else {
        let spanIdx = Int32(spansArr.count)
        spansArr.append((start: Int32(store.count), count: Int32(idxs.count)))
        store.append(contentsOf: idxs)
        data[tileKey] = -(spanIdx + 1)
      }
    }

    tileData = data
    multiSpans = spansArr
    tzNames = namesArr
    multiStore = store
  }

  public func dataVersion() -> String {
    return preindexData.version
  }

  private func lngLatToTile(lng: Double, lat: Double, zoom: Int32) -> (x: Int32, y: Int32) {
    let n = pow(2.0, Double(zoom))
    var x = Int32((lng + 180.0) / 360.0 * n)
    let latRad = lat * .pi / 180.0
    var y = Int32((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n)

    // Handle edge cases
    x = max(0, min(x, Int32(n) - 1))
    y = max(0, min(y, Int32(n) - 1))

    return (x, y)
  }

  @inline(__always)
  private func tileKey(zoom: Int32, highX: Int32, highY: Int32) -> Int64 {
    let shift = idxZoom - zoom
    return Int64(zoom) << 26 | Int64(highX >> shift) << 13 | Int64(highY >> shift)
  }

  @inline(__always)
  private func firstName(for val: Int32) -> String {
    if val >= 0 { return tzNames[Int(val)] }
    let span = multiSpans[Int(-(val + 1))]
    return tzNames[Int(multiStore[Int(span.start)])]
  }

  // Non-throwing fast path used by DefaultFinder — mirrors Go's FuzzyFinder.GetTimezoneName.
  // One dict lookup per zoom level (vs two previously); returns nil on miss.
  @inline(__always)
  func fuzzyGetTimezone(lng: Double, lat: Double) -> String? {
    let (highX, highY) = lngLatToTile(lng: lng, lat: lat, zoom: idxZoom)
    for zoom in aggZoom...idxZoom {
      if let val = tileData[tileKey(zoom: zoom, highX: highX, highY: highY)] {
        return firstName(for: val)
      }
    }
    return nil
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    guard (-180.0...180.0).contains(lng) && (-90.0...90.0).contains(lat) else {
      throw TZFError.invalidCoordinates
    }
    let (highX, highY) = lngLatToTile(lng: lng, lat: lat, zoom: idxZoom)
    for zoom in aggZoom...idxZoom {
      if let val = tileData[tileKey(zoom: zoom, highX: highX, highY: highY)] {
        return firstName(for: val)
      }
    }
    throw TZFError.noTimezoneFound
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    guard (-180.0...180.0).contains(lng) && (-90.0...90.0).contains(lat) else {
      throw TZFError.invalidCoordinates
    }
    let (highX, highY) = lngLatToTile(lng: lng, lat: lat, zoom: idxZoom)
    for zoom in aggZoom...idxZoom {
      guard let val = tileData[tileKey(zoom: zoom, highX: highX, highY: highY)] else { continue }
      if val >= 0 { return [tzNames[Int(val)]] }
      let span = multiSpans[Int(-(val + 1))]
      return (span.start..<(span.start + span.count)).map { tzNames[Int(multiStore[Int($0)])] }
    }
    throw TZFError.noTimezoneFound
  }

  private func tileToPolygon(x: Int32, y: Int32, z: Int32) -> [[Double]] {
    let n = pow(2.0, Double(z))

    let lngMin = Double(x) / n * 360.0 - 180.0
    let latMinRad = atan(sinh((1.0 - Double(y + 1) / n * 2.0) * .pi))
    let latMin = latMinRad * 180.0 / .pi

    let lngMax = Double(x + 1) / n * 360.0 - 180.0
    let latMaxRad = atan(sinh((1.0 - Double(y) / n * 2.0) * .pi))
    let latMax = latMaxRad * 180.0 / .pi

    return [
      [lngMin, latMin],
      [lngMax, latMin],
      [lngMax, latMax],
      [lngMin, latMax],
      [lngMin, latMin],
    ]
  }

  /// Convert all preindex tiles to GeoJSON FeatureCollection.
  public func toGeoJSON() -> GeoJSONFeatureCollection {
    var grouped: [String: GeoJSONMultiPolygonCoordinates] = [:]

    for key in preindexData.keys {
      let tileRing = tileToPolygon(x: key.x, y: key.y, z: key.z)
      grouped[key.name, default: []].append([tileRing])
    }

    let features = grouped.keys.sorted().map { timezoneName in
      GeoJSONFeature(
        type: "Feature",
        properties: GeoJSONProperties(tzid: timezoneName),
        geometry: GeoJSONGeometry(
          type: "MultiPolygon",
          coordinates: grouped[timezoneName] ?? []
        )
      )
    }

    return GeoJSONFeatureCollection(type: "FeatureCollection", features: features)
  }

  /// Convert one timezone's preindex tiles to GeoJSON FeatureCollection.
  ///
  /// - Parameter timezoneName: IANA timezone name, for example "Asia/Tokyo"
  /// - Returns: GeoJSON collection if found, otherwise nil.
  public func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    var coordinates: GeoJSONMultiPolygonCoordinates = []

    for key in preindexData.keys where key.name == timezoneName {
      let tileRing = tileToPolygon(x: key.x, y: key.y, z: key.z)
      coordinates.append([tileRing])
    }

    if coordinates.isEmpty {
      return nil
    }

    let feature = GeoJSONFeature(
      type: "Feature",
      properties: GeoJSONProperties(tzid: timezoneName),
      geometry: GeoJSONGeometry(type: "MultiPolygon", coordinates: coordinates)
    )

    return GeoJSONFeatureCollection(type: "FeatureCollection", features: [feature])
  }
}

// MARK: - Errors

/// Represents possible errors that can occur during timezone lookup operations.
public enum TZFError: Error {
  /// Indicates that the provided coordinates are outside the valid range
  /// (longitude: -180 to 180, latitude: -90 to 90)
  case invalidCoordinates

  /// Indicates that no timezone was found for the given coordinates
  case noTimezoneFound

  /// Indicates an error occurred while loading or processing the timezone data
  case dataError
}

/// Represents errors specific to the Finder implementation.
public enum FinderError: Error {
  case noTimezoneFound
}

// MARK: - Finder

/// A timezone finder that performs point-in-polygon tests against topology-compressed
/// timezone boundary data (CompressedTopoTimezones format).
///
/// Finder decodes the shared-edge topology and polyline-compressed coordinates from
/// `combined-with-oceans.topology.compress.topo.bin`, then builds Polygon objects for
/// efficient containment testing.
///
/// Features:
/// - Shared-edge deduplication (boundaries stored once, referenced by ID)
/// - Polyline coordinate compression (delta + zigzag encoding, scale 1e5)
/// - Polygon boundary support with hole (enclave) handling
/// - Bounding-box pre-filter for fast rejection
/// - Optional 1°×1° grid index for O(1) candidate reduction (embedded in data file)
public class Finder: F {
  private struct ProcessedTimezone {
    let name: String
    let polygons: [Polygon]
    let unionRect: Rect
  }
  private let processedTimezones: [ProcessedTimezone]
  private let version: String
  // Flat grid storage: no per-cell heap allocation, no ARC on lookup.
  // gridIndex maps packed(floor(lng), floor(lat)) → (start, count) into candidateStore.
  // Key: low 16 bits = Int16(floor(lng)), high 16 bits = Int16(floor(lat)).
  // nil when the data file has no embedded GridIndex (falls back to linear scan).
  private struct GridSpan { let start: Int32; let count: Int32 }
  private let gridIndex: [Int32: GridSpan]?
  private let candidateStore: [Int32]

  public init() throws {
    let bundle = Bundle.module

    guard
      let url = bundle.url(
        forResource: "combined-with-oceans.topology.compress.topo", withExtension: "bin")
    else {
      throw TZFError.dataError
    }

    let rawData = try Data(contentsOf: url)
    let topoData = try Tzf_V1_CompressedTopoTimezones(serializedBytes: rawData)
    self.version = topoData.version

    // Decode shared edges once, indexed by edge ID.
    var edges = [[Point]](repeating: [], count: topoData.sharedEdges.count)
    for edge in topoData.sharedEdges {
      edges[Int(edge.id)] = decodePolylineBytes(edge.points)
    }

    // Build processed timezones with pre-decoded polygons.
    var processed: [ProcessedTimezone] = []
    for tz in topoData.timezones {
      var polygons: [Polygon] = []
      for poly in tz.polygons {
        let exterior = expandCompressedRing(poly.exterior, edges: edges)
        let holes = poly.holes.map { expandCompressedRing($0.exterior, edges: edges) }
        guard !exterior.isEmpty else { continue }
        polygons.append(Polygon.new(exterior: exterior, holes: holes))
      }
      guard !polygons.isEmpty else { continue }
      var minX = polygons[0].rect.min.x, minY = polygons[0].rect.min.y
      var maxX = polygons[0].rect.max.x, maxY = polygons[0].rect.max.y
      for p in polygons.dropFirst() {
        minX = min(minX, p.rect.min.x); minY = min(minY, p.rect.min.y)
        maxX = max(maxX, p.rect.max.x); maxY = max(maxY, p.rect.max.y)
      }
      let unionRect = Rect(min: Point(x: minX, y: minY), max: Point(x: maxX, y: maxY))
      processed.append(ProcessedTimezone(name: tz.name, polygons: polygons, unionRect: unionRect))
    }
    self.processedTimezones = processed

    // Decode the embedded GridIndex into flat storage for O(1) cell lookup with no ARC.
    // candidateStore is one contiguous [Int32]; gridIndex maps packed keys to (start,count)
    // spans — GridSpan is a struct, so dict lookups incur no retain/release.
    if topoData.hasGridIndex {
      var store = [Int32]()
      var indexMap = [Int32: GridSpan]()
      indexMap.reserveCapacity(topoData.gridIndex.cells.count)
      for cell in topoData.gridIndex.cells {
        let key = Int32(Int16(cell.lng)) | (Int32(Int16(cell.lat)) << 16)
        let start = Int32(store.count)
        for idx in cell.tzIndices { store.append(Int32(idx)) }
        indexMap[key] = GridSpan(start: start, count: Int32(cell.tzIndices.count))
      }
      self.gridIndex = indexMap
      self.candidateStore = store
    } else {
      self.gridIndex = nil
      self.candidateStore = []
    }
  }

  private func toFeature(name: String, polygons: [Polygon]) -> GeoJSONFeature {
    let coordinates = polygons.map { polygon -> GeoJSONPolygonCoordinates in
      var rings: GeoJSONPolygonCoordinates = []
      rings.append(polygon.exterior.map { [$0.x, $0.y] })
      for hole in polygon.holes {
        rings.append(hole.map { [$0.x, $0.y] })
      }
      return rings
    }
    return GeoJSONFeature(
      type: "Feature",
      properties: GeoJSONProperties(tzid: name),
      geometry: GeoJSONGeometry(type: "MultiPolygon", coordinates: coordinates)
    )
  }

  /// Convert all timezone polygons to GeoJSON FeatureCollection.
  public func toGeoJSON() -> GeoJSONFeatureCollection {
    let features = processedTimezones.map { toFeature(name: $0.name, polygons: $0.polygons) }
    return GeoJSONFeatureCollection(type: "FeatureCollection", features: features)
  }

  /// Convert one timezone polygon set to GeoJSON FeatureCollection.
  ///
  /// - Parameter timezoneName: IANA timezone name, for example "Asia/Tokyo"
  /// - Returns: One-feature GeoJSON collection when found, nil when missing.
  public func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    guard let tz = processedTimezones.first(where: { $0.name == timezoneName }) else {
      return nil
    }
    let feature = toFeature(name: tz.name, polygons: tz.polygons)
    return GeoJSONFeatureCollection(type: "FeatureCollection", features: [feature])
  }

  public func dataVersion() -> String {
    return version
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    let point = Point(x: lng, y: lat)
    if let index = gridIndex {
      let key = Int32(Int16(floor(lng))) | (Int32(Int16(floor(lat))) << 16)
      if let span = index[key] {
        // Single-candidate shortcut: grid guarantees exactly one timezone for this cell.
        if span.count == 1 {
          return processedTimezones[Int(candidateStore[Int(span.start)])].name
        }
        for i in span.start..<(span.start + span.count) {
          let tz = processedTimezones[Int(candidateStore[Int(i)])]
          guard tz.unionRect.containsPoint(point) else { continue }
          for polygon in tz.polygons {
            if polygon.containsPoint(point) { return tz.name }
          }
        }
        // PIP found no match among candidates — fall through to full scan.
      }
      // Cell absent or PIP miss: full linear scan as fallback (matches Go/Rust behaviour).
    }
    for tz in processedTimezones {
      guard tz.unionRect.containsPoint(point) else { continue }
      for polygon in tz.polygons {
        if polygon.containsPoint(point) { return tz.name }
      }
    }
    throw FinderError.noTimezoneFound
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    let point = Point(x: lng, y: lat)
    var results: [String] = []

    if let index = gridIndex {
      let key = Int32(Int16(floor(lng))) | (Int32(Int16(floor(lat))) << 16)
      if let span = index[key], span.count > 0 {
        for i in span.start..<(span.start + span.count) {
          let tz = processedTimezones[Int(candidateStore[Int(i)])]
          guard tz.unionRect.containsPoint(point) else { continue }
          for polygon in tz.polygons {
            if polygon.containsPoint(point) { results.append(tz.name); break }
          }
        }
        if !results.isEmpty {
          results.sort()
          return results
        }
        // Cell present but PIP found nothing — fall through to full scan.
      }
      // Cell absent or PIP miss: full linear scan as fallback.
    }
    for tz in processedTimezones {
      guard tz.unionRect.containsPoint(point) else { continue }
      for polygon in tz.polygons {
        if polygon.containsPoint(point) { results.append(tz.name); break }
      }
    }
    if results.isEmpty { throw FinderError.noTimezoneFound }
    results.sort()
    return results
  }
}

// MARK: - DefaultFinder

/// The default finder implementation that combines both PreindexFinder and Finder
/// for optimal performance and accuracy.
///
/// This finder first attempts to use the PreindexFinder for fast lookups using
/// pre-indexed tiles. If that fails, it falls back to the more accurate but slower
/// Finder implementation that uses polygon data.
public class DefaultFinder: F {
  private let preindexFinder: PreindexFinder
  private let topoFinder: Finder

  public init() throws {
    self.preindexFinder = try PreindexFinder()
    self.topoFinder = try Finder()
  }

  public func dataVersion() -> String {
    return "\(preindexFinder.dataVersion())/\(topoFinder.dataVersion())"
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    if let result = preindexFinder.fuzzyGetTimezone(lng: lng, lat: lat) {
      return result
    }
    return try topoFinder.getTimezone(lng: lng, lat: lat)
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    do {
      return try preindexFinder.getTimezones(lng: lng, lat: lat)
    } catch {
      return try topoFinder.getTimezones(lng: lng, lat: lat)
    }
  }

  /// Convert all timezone polygons to GeoJSON FeatureCollection.
  public func toGeoJSON() -> GeoJSONFeatureCollection {
    return topoFinder.toGeoJSON()
  }

  /// Convert one timezone polygon set to GeoJSON FeatureCollection.
  ///
  /// - Parameter timezoneName: IANA timezone name, for example "Asia/Tokyo"
  /// - Returns: One-feature GeoJSON collection when found, nil when missing.
  public func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    return topoFinder.getTimezoneGeoJSON(timezoneName: timezoneName)
  }
}
