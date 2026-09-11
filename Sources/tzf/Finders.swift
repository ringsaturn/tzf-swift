import Dispatch
import Foundation
import geometry

// MARK: - Errors

/// Errors raised by the timezone finders.
public enum TZFError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The provided coordinates are non-finite or outside the valid range
  /// (longitude: -180 to 180, latitude: -90 to 90).
  case invalidCoordinates

  /// No timezone was found for the given coordinates.
  case noTimezoneFound

  /// The bundled timezone data could not be located or read.
  case dataError

  /// The `.tzb` bytes violate the format's structural rules.
  case malformed(String)

  /// The bytes are a memory-image (`.tzm`, M profile) file, which tzf-swift
  /// does not consume: it exists for the Go runtime's zero-copy ring
  /// aliasing. Use the `.tzb` file.
  case unsupportedProfile

  /// The file carries no FUZZY (preindex) section.
  case noFuzzySection

  /// A timezone index is out of range.
  case indexOutOfRange

  public var description: String {
    switch self {
    case .invalidCoordinates: return "tzf: invalid coordinates"
    case .noTimezoneFound: return "tzf: no timezone found"
    case .dataError: return "tzf: bundled data unavailable"
    case .malformed(let what): return "tzf: malformed .tzb file: \(what)"
    case .unsupportedProfile: return "tzf: memory-image (.tzm) files are not supported; use .tzb"
    case .noFuzzySection: return "tzf: file has no FUZZY section"
    case .indexOutOfRange: return "tzf: timezone index out of range"
    }
  }
}

// MARK: - Bundled data

/// Access to the `.tzb` artifact bundled with the package.
public enum TZFDist {
  /// The bundled tzf-dist `lite.tzb` bytes: the topology-simplified dataset
  /// with its FUZZY preindex, ~4 MB.
  public static func loadLiteTZB() throws -> Data {
    guard let url = Bundle.module.url(forResource: "lite", withExtension: "tzb") else {
      throw TZFError.dataError
    }
    return try Data(contentsOf: url)
  }
}

// MARK: - F

/// The interface every timezone finder implements.
public protocol F: Sendable {
  /// Returns the dataset release the finder was built from (e.g. `2026c`).
  func dataVersion() -> String

  /// Returns the timezone for a geographic coordinate.
  ///
  /// - Parameters:
  ///   - lng: The longitude in decimal degrees (-180 to 180)
  ///   - lat: The latitude in decimal degrees (-90 to 90)
  /// - Returns: The IANA timezone identifier
  /// - Throws: `TZFError.invalidCoordinates` for non-finite or out-of-range
  ///   input; `TZFError.noTimezoneFound` when no timezone covers the point.
  func getTimezone(lng: Double, lat: Double) throws -> String

  /// Returns all timezones covering a geographic coordinate, sorted
  /// lexicographically. A point exactly on a shared border belongs to every
  /// touching timezone. Always polygon-exact.
  ///
  /// - Throws: `TZFError.invalidCoordinates` for non-finite or out-of-range
  ///   input; `TZFError.noTimezoneFound` when no timezone covers the point.
  func getTimezones(lng: Double, lat: Double) throws -> [String]

  /// Returns all timezone names in the dataset, in dataset order.
  func timezoneNames() -> [String]

  /// Converts all timezone boundaries to a GeoJSON FeatureCollection.
  func toGeoJSON() -> GeoJSONFeatureCollection

  /// Converts one timezone's boundaries to a GeoJSON FeatureCollection.
  ///
  /// - Parameter timezoneName: IANA timezone name, for example "Asia/Tokyo"
  /// - Returns: The collection if found, otherwise nil.
  func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection?

  /// Converts the whole FUZZY preindex to a GeoJSON FeatureCollection: one
  /// Feature per timezone that owns at least one tile, in dataset order; a
  /// boundary tile appears in every timezone it names. Returns nil when the
  /// file carries no FUZZY section.
  func toPreindexGeoJSON() -> GeoJSONFeatureCollection?

  /// Converts one timezone's FUZZY preindex tiles to a GeoJSON
  /// FeatureCollection: one Feature whose MultiPolygon holds each tile's
  /// bounding rectangle — the area where `getTimezone` answers from the
  /// preindex fast path instead of exact point-in-polygon. Tiles are ordered
  /// coarsest zoom first.
  ///
  /// Returns nil when the file carries no FUZZY section, the dataset does not
  /// contain the name, or no preindex tile names it.
  func getTimezonePreindexGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection?
}

// MARK: - Materialized polygon finder

/// One timezone's polygons.
struct Item: Sendable {
  let name: String
  let polys: [I32Polygon]

  /// Timezone polygons tile the globe, so a query that lands exactly on a
  /// shared border must belong to both neighbours rather than to neither.
  @inline(__always)
  func contains(_ sp: Point) -> Bool {
    for poly in polys where poly.containsScaledPoint(sp, allowOnEdge: true) {
      return true
    }
    return false
  }
}

/// The dense 1°×1° GRID candidate index, copied out of the file so queries
/// probe a flat array instead of a hash map.
struct DenseGrid: Sendable {
  let lngMin: Int
  let latMin: Int
  let lngCells: Int
  let latCells: Int
  let words: [UInt32]
  let cands: [UInt16]

  init?(reader: TZBReader) {
    guard let (g, words, cands) = reader.gridArrays() else { return nil }
    lngMin = Int(g.lngMin)
    latMin = Int(g.latMin)
    lngCells = Int(g.lngCells)
    latCells = Int(g.latCells)
    self.words = words
    self.cands = cands
  }

  /// The candidate range for an in-domain (lng, lat): count 0 means no
  /// candidate covers the point. Offsets were bounds-checked at open.
  @inline(__always)
  func cellRange(lng: Double, lat: Double) -> (off: Int, count: Int) {
    let cx = Int(lng.rounded(.down)) - lngMin
    let cy = Int(lat.rounded(.down)) - latMin
    if cx < 0 || cy < 0 || cx >= lngCells || cy >= latCells {
      return (0, 0)
    }
    let word = words[cy * lngCells + cx]
    return (Int(word & 0x0fff_ffff), Int(word >> 28))
  }

  @inline(__always)
  func candidate(_ off: Int) -> Int {
    Int(cands[off])
  }
}

/// The materialized point-in-polygon finder behind `DefaultFinder`.
final class PolyFinder: Sendable {
  let items: [Item]
  let grid: DenseGrid?
  let version: String

  init(items: [Item], grid: DenseGrid?, version: String) {
    self.items = items
    self.grid = grid
    self.version = version
  }

  /// The first containing item index in source order, for an in-domain
  /// point.
  @inline(__always)
  func lookup(lng: Double, lat: Double) -> Int? {
    let sp = Point(x: lng * i32Scale, y: lat * i32Scale)
    if let grid = grid {
      let (off, count) = grid.cellRange(lng: lng, lat: lat)
      if count == 0 {
        return nil
      }
      // Single-candidate short-circuit: skip PIP when there is only one
      // candidate and we are away from the antimeridian / pole edges.
      if count == 1 && lng > -179.0 && lng < 179.0 && lat > -89.0 && lat < 89.0 {
        return grid.candidate(off)
      }
      for i in 0..<count {
        let idx = grid.candidate(off + i)
        if items[idx].contains(sp) {
          return idx
        }
      }
      return nil
    }
    for (idx, item) in items.enumerated() where item.contains(sp) {
      return idx
    }
    return nil
  }

  /// All matching item indices for an in-domain point, sorted by name.
  func lookupAll(lng: Double, lat: Double) -> [Int] {
    let sp = Point(x: lng * i32Scale, y: lat * i32Scale)
    var res = [Int]()
    if let grid = grid {
      let (off, count) = grid.cellRange(lng: lng, lat: lat)
      for i in 0..<count {
        let idx = grid.candidate(off + i)
        if items[idx].contains(sp) {
          res.append(idx)
        }
      }
    } else {
      for (idx, item) in items.enumerated() where item.contains(sp) {
        res.append(idx)
      }
    }
    res.sort { items[$0].name < items[$1].name }
    return res
  }
}

/// Builds the finder items. Assembly cost is dominated by the per-ring
/// YStripes build and every timezone is independent, so the work fans out
/// across the CPUs.
func assembleItems(names: [String], polygons: [[ExpandedPolygon]]) -> [Item] {
  let n = names.count
  var slots = [Item?](repeating: nil, count: n)
  slots.withUnsafeMutableBufferPointer { out in
    // Each iteration writes exactly one distinct slot; there is no shared
    // mutable state beyond the disjoint writes.
    nonisolated(unsafe) let dst = out
    DispatchQueue.concurrentPerform(iterations: n) { i in
      dst[i] = Item(
        name: names[i],
        polys: polygons[i].map { I32Polygon(exterior: $0.exterior, holes: $0.holes) })
    }
  }
  return slots.map { $0! }
}

// MARK: - FUZZY fast path

/// The preindex tile fast path rebuilt out of a file's FUZZY section. A
/// query it cannot answer falls through to the polygon finder.
final class FuzzyIndex: Sendable {
  let idxZoom: UInt8
  let aggZoom: UInt8
  /// Value ≥ 0 → single timezone index. Value < 0 → `-(spanIdx + 1)`, where
  /// `spanIdx` indexes `multiSpans` for a `(start, count)` into `multiStore`.
  let tiles: [UInt64: Int32]
  let multiSpans: [(start: Int32, count: Int32)]
  let multiStore: [UInt16]
  /// Every tile key in ascending order (coarsest zoom first, since the zoom
  /// lives in the key's high bits); the deterministic order for exports.
  let sortedKeys: [UInt64]

  /// Rebuilds the preindex map from a file's FUZZY section: one pass over the
  /// sorted tile keys. `nil` when the file carries no FUZZY section.
  init?(reader: TZBReader) throws {
    guard let (idxZoom, aggZoom) = reader.fuzzyZooms else { return nil }
    let entries = try reader.fuzzyEntries()
    var tiles = [UInt64: Int32]()
    tiles.reserveCapacity(entries.count)
    var spans = [(start: Int32, count: Int32)]()
    var store = [UInt16]()
    var keys = [UInt64]()
    keys.reserveCapacity(entries.count)
    for (key, indices) in entries {
      keys.append(key)
      if indices.count == 1 {
        tiles[key] = Int32(indices[0])
      } else {
        let spanIdx = Int32(spans.count)
        spans.append((start: Int32(store.count), count: Int32(indices.count)))
        store.append(contentsOf: indices)
        tiles[key] = -(spanIdx + 1)
      }
    }
    self.idxZoom = idxZoom
    self.aggZoom = aggZoom
    self.tiles = tiles
    self.multiSpans = spans
    self.multiStore = store
    self.sortedKeys = keys
  }

  @inline(__always)
  private func first(_ value: Int32) -> Int {
    if value >= 0 { return Int(value) }
    let span = multiSpans[Int(-(value + 1))]
    return Int(multiStore[Int(span.start)])
  }

  @inline(__always)
  private func indices(_ value: Int32) -> ArraySlice<UInt16> {
    if value >= 0 { return [UInt16(value)][...] }
    let span = multiSpans[Int(-(value + 1))]
    return multiStore[Int(span.start)..<Int(span.start + span.count)]
  }

  /// The tile answer for an in-domain (lng, lat), coarsest zoom first;
  /// multi-name tiles resolve to the group's first entry (first-listed
  /// wins). `nil` means no tile covers the point.
  @inline(__always)
  func get(lng: Double, lat: Double) -> Int? {
    let tile = TileID(lng: lng, lat: lat, zoom: UInt32(idxZoom))
    for z in aggZoom...idxZoom {
      if let value = tiles[tile.shift(idxZoom - z).raw] {
        return first(value)
      }
    }
    return nil
  }

  /// All tile keys carrying any of the given timezone indices, ascending.
  func tileKeys(for wanted: Set<UInt16>) -> [UInt64] {
    sortedKeys.filter { key in
      indices(tiles[key]!).contains { wanted.contains($0) }
    }
  }

  /// Keys grouped by the timezone index they carry (a boundary tile lands in
  /// every group it names); each group ascending.
  func tileKeysGrouped() -> [UInt16: [UInt64]] {
    var grouped = [UInt16: [UInt64]]()
    for key in sortedKeys {
      for idx in indices(tiles[key]!) {
        grouped[idx, default: []].append(key)
      }
    }
    return grouped
  }
}

// MARK: - Shared GeoJSON helpers

/// Preindex export shared by both finders: `entries` are the FUZZY tiles in
/// ascending key order.
enum PreindexExport {
  static func timezone(
    name: String, names: [String], keysFor: (Set<UInt16>) -> [UInt64]
  ) -> GeoJSONFeatureCollection? {
    // The same name may map to more than one directory item; a preindex
    // tile may name any of them.
    var wanted = Set<UInt16>()
    for (i, n) in names.enumerated() where n == name {
      if let idx = UInt16(exactly: i) { wanted.insert(idx) }
    }
    if wanted.isEmpty {
      return nil
    }
    let keys = keysFor(wanted)
    if keys.isEmpty {
      return nil
    }
    return GeoJSON.collection([GeoJSON.feature(name: name, tileKeys: keys)])
  }

  static func all(names: [String], grouped: [UInt16: [UInt64]]) -> GeoJSONFeatureCollection {
    var features = [GeoJSONFeature]()
    for (i, name) in names.enumerated() {
      guard let idx = UInt16(exactly: i), let keys = grouped[idx] else { continue }
      features.append(GeoJSON.feature(name: name, tileKeys: keys))
    }
    return GeoJSON.collection(features)
  }
}

// MARK: - DefaultFinder

/// The recommended finder: FUZZY preindex fast path over materialized
/// polygon geometry, loaded from a `.tzb` file.
///
/// `getTimezone` answers from the preindex tile when one covers the point
/// (the vast majority of queries) and falls back to exact point-in-polygon
/// otherwise; `getTimezones` always uses the polygon scan, as the
/// polygon-exact escape hatch. Files without a FUZZY section get the plain
/// polygon finder.
///
/// Creating a finder is expensive — build one and share it.
public final class DefaultFinder: F {
  private let fuzzy: FuzzyIndex?
  private let finder: PolyFinder

  /// Creates the finder from the bundled tzf-dist `lite.tzb` data.
  public convenience init() throws {
    try self.init(tzb: try TZFDist.loadLiteTZB())
  }

  /// Builds a finder from TZF embedded binary (`.tzb`) bytes by expanding
  /// the geometry into the materialized polygon engine at load time. `data`
  /// is only read during loading. When the file carries a FUZZY section it
  /// becomes the `getTimezone` fast path.
  ///
  /// - Throws: `TZFError` when the bytes are not a structurally valid
  ///   E-profile (`.tzb`) file.
  public init(tzb data: Data) throws {
    let reader = try TZBReader(data: data)
    let fuzzy = try FuzzyIndex(reader: reader)
    let grid = DenseGrid(reader: reader)
    let expanded = try reader.expand()
    self.fuzzy = fuzzy
    self.finder = PolyFinder(
      items: assembleItems(names: expanded.names, polygons: expanded.polygons),
      grid: grid,
      version: expanded.version)
  }

  public func dataVersion() -> String {
    finder.version
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    guard TZB.coordinateInDomain(lng: lng, lat: lat) else {
      throw TZFError.invalidCoordinates
    }
    if let fuzzy = fuzzy, let idx = fuzzy.get(lng: lng, lat: lat) {
      return finder.items[idx].name
    }
    guard let idx = finder.lookup(lng: lng, lat: lat) else {
      throw TZFError.noTimezoneFound
    }
    return finder.items[idx].name
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    guard TZB.coordinateInDomain(lng: lng, lat: lat) else {
      throw TZFError.invalidCoordinates
    }
    let idxs = finder.lookupAll(lng: lng, lat: lat)
    if idxs.isEmpty {
      throw TZFError.noTimezoneFound
    }
    return idxs.map { finder.items[$0].name }
  }

  public func timezoneNames() -> [String] {
    finder.items.map(\.name)
  }

  public func toGeoJSON() -> GeoJSONFeatureCollection {
    GeoJSON.collection(finder.items.map { GeoJSON.feature(name: $0.name, polygons: $0.polys) })
  }

  public func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    let features = finder.items.filter { $0.name == timezoneName }
      .map { GeoJSON.feature(name: $0.name, polygons: $0.polys) }
    return features.isEmpty ? nil : GeoJSON.collection(features)
  }

  public func toPreindexGeoJSON() -> GeoJSONFeatureCollection? {
    guard let fuzzy = fuzzy else { return nil }
    return PreindexExport.all(names: timezoneNames(), grouped: fuzzy.tileKeysGrouped())
  }

  public func getTimezonePreindexGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    guard let fuzzy = fuzzy else { return nil }
    return PreindexExport.timezone(name: timezoneName, names: timezoneNames()) {
      fuzzy.tileKeys(for: $0)
    }
  }
}

// MARK: - EmbeddedFinder

/// The low-memory finder: queries TZF embedded binary (`.tzb`) bytes in
/// place, without expanding the geometry. Total footprint is roughly the
/// file itself (the bundled lite data is ~4 MB) plus the name table.
///
/// `getTimezone` consults the file's FUZZY preindex first and falls back to
/// the compressed-geometry scan; results match `DefaultFinder` over the same
/// file, only slower on boundary queries (microseconds instead of hundreds
/// of nanoseconds).
public final class EmbeddedFinder: F {
  private let reader: TZBReader
  private let names: [String]

  /// Creates the finder over the bundled tzf-dist `lite.tzb` data.
  public convenience init() throws {
    try self.init(tzb: try TZFDist.loadLiteTZB())
  }

  /// Builds a finder that queries a private copy of `data` in place.
  ///
  /// - Throws: `TZFError` when the bytes are not a structurally valid
  ///   E-profile (`.tzb`) file. Memory images (`.tzm`) are rejected with
  ///   `TZFError.unsupportedProfile`.
  public init(tzb data: Data) throws {
    let reader = try TZBReader(data: data)
    self.reader = reader
    self.names = try reader.names()
  }

  public func dataVersion() -> String {
    reader.dataVersion
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    guard TZB.coordinateInDomain(lng: lng, lat: lat) else {
      throw TZFError.invalidCoordinates
    }
    if reader.hasFuzzy, let idx = try reader.fuzzyLookup(lng: lng, lat: lat) {
      return names[Int(idx)]
    }
    guard let idx = try reader.lookup(lng: lng, lat: lat) else {
      throw TZFError.noTimezoneFound
    }
    return names[Int(idx)]
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    guard TZB.coordinateInDomain(lng: lng, lat: lat) else {
      throw TZFError.invalidCoordinates
    }
    let idxs = try reader.lookupAll(lng: lng, lat: lat)
    if idxs.isEmpty {
      throw TZFError.noTimezoneFound
    }
    return idxs.map { names[Int($0)] }
  }

  public func timezoneNames() -> [String] {
    names
  }

  /// Converts all timezone boundaries to a GeoJSON FeatureCollection.
  ///
  /// Unlike `DefaultFinder`, which exports polygons it already holds, this
  /// decodes the whole file's geometry on demand — roughly the cost of
  /// loading an expanded finder. A timezone that fails to decode is omitted.
  public func toGeoJSON() -> GeoJSONFeatureCollection {
    var features = [GeoJSONFeature]()
    features.reserveCapacity(names.count)
    for (i, name) in names.enumerated() {
      guard let polys = try? reader.expandTimezone(UInt32(i)) else { continue }
      features.append(GeoJSON.feature(name: name, polygons: polys))
    }
    return GeoJSON.collection(features)
  }

  /// Converts one timezone's boundaries to a GeoJSON FeatureCollection,
  /// decoding only that timezone's rings. Returns nil when the dataset does
  /// not contain the name or its geometry fails to decode.
  public func getTimezoneGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    var features = [GeoJSONFeature]()
    for (i, name) in names.enumerated() where name == timezoneName {
      guard let polys = try? reader.expandTimezone(UInt32(i)) else { return nil }
      features.append(GeoJSON.feature(name: name, polygons: polys))
    }
    return features.isEmpty ? nil : GeoJSON.collection(features)
  }

  public func toPreindexGeoJSON() -> GeoJSONFeatureCollection? {
    guard reader.hasFuzzy, let entries = try? reader.fuzzyEntries() else { return nil }
    var grouped = [UInt16: [UInt64]]()
    for (key, idxs) in entries {
      for idx in idxs {
        grouped[idx, default: []].append(key)
      }
    }
    return PreindexExport.all(names: names, grouped: grouped)
  }

  public func getTimezonePreindexGeoJSON(timezoneName: String) -> GeoJSONFeatureCollection? {
    guard reader.hasFuzzy, let entries = try? reader.fuzzyEntries() else { return nil }
    return PreindexExport.timezone(name: timezoneName, names: names) { wanted in
      // The FUZZY key array is stored sorted, so the filtered keys keep the
      // coarsest-zoom-first order DefaultFinder produces.
      entries.filter { $0.indices.contains { wanted.contains($0) } }.map(\.key)
    }
  }
}
