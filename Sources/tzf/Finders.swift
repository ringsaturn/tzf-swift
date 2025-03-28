/// tzf for swift.
///
/// A Swift package for timezone lookup by geographic coordinates (longitude/latitude).
/// This package uses a simplified polygon data structure for timezone boundaries.
/// The underlying data has been pre-simplified to reduce size and improve performance,
/// while still maintaining reasonable accuracy for most use cases.
///
/// Important Notes:
/// - The timezone boundary data has been simplified to reduce complexity
/// - Accuracy may be reduced around timezone borders
/// - For high-precision requirements, consider using official IANA timezone data
///
/// The package offers three finder implementations:
/// - `PreindexFinder`: Uses pre-indexed map tiles for fast lookups
/// - `Finder`: Uses polygon-based lookups with simplified boundary data
/// - `DefaultFinder`: Combines both approaches for optimal results
///
/// Other related projects:
///
/// | Language or Sever         | Link                                                                    | Note                |
/// | ------------------------- | ----------------------------------------------------------------------- | ------------------- |
/// | Go                        | [`ringsaturn/tzf`](https://github.com/ringsaturn/tzf)                   |                     |
/// | Ruby                      | [`HarlemSquirrel/tzf-rb`](https://github.com/HarlemSquirrel/tzf-rb)     | build with tzf-rs   |
/// | Rust                      | [`ringsaturn/tzf-rs`](https://github.com/ringsaturn/tzf-rs)             |                     |
/// | Swift                     | [`ringsaturn/tzf-swift`](https://github.com/ringsaturn/tzf-swift)       |                     |
/// | Python                    | [`ringsaturn/tzfpy`](https://github.com/ringsaturn/tzfpy)               | build with tzf-rs   |
/// | HTTP API                  | [`ringsaturn/tzf-server`](https://github.com/ringsaturn/tzf-server)     | build with tzf      |
/// | HTTP API                  | [`racemap/rust-tz-service`](https://github.com/racemap/rust-tz-service) | build with tzf-rs   |
/// | Redis Server              | [`ringsaturn/tzf-server`](https://github.com/ringsaturn/tzf-server)     | build with tzf      |
/// | Redis Server              | [`ringsaturn/redizone`](https://github.com/ringsaturn/redizone)         | build with tzf-rs   |
/// | JS via Wasm(browser only) | [`ringsaturn/tzf-wasm`](https://github.com/ringsaturn/tzf-wasm)         | build with tzf-rs   |
/// | Online                    | [`ringsaturn/tzf-web`](https://github.com/ringsaturn/tzf-web)           | build with tzf-wasm |
import Foundation
import SwiftProtobuf
import geometry

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
}

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
  private let tileCache: [String: [String]]

  public init() throws {
    let bundle = Bundle.module

    guard
      let preindexURL = bundle.url(
        forResource: "combined-with-oceans.reduce.preindex", withExtension: "bin")
    else {
      throw TZFError.dataError
    }

    let preindexDataBytes = try Data(contentsOf: preindexURL)
    preindexData = try Tzf_V1_PreindexTimezones(serializedBytes: preindexDataBytes)
    idxZoom = preindexData.idxZoom
    aggZoom = preindexData.aggZoom

    // Initialize the tile cache with arrays of timezone names
    var cache = [String: [String]]()
    for key in preindexData.keys {
      let tileKey = "\(key.z):\(key.x):\(key.y)"
      if cache[tileKey] == nil {
        cache[tileKey] = [key.name]
      } else {
        cache[tileKey]?.append(key.name)
      }
    }

    // Sort timezone names for each tile
    for (key, value) in cache {
      cache[key] = value.sorted()
    }

    tileCache = cache
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

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    let timezones = try getTimezones(lng: lng, lat: lat)
    guard let timezone = timezones.first else {
      throw TZFError.noTimezoneFound
    }
    return timezone
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    // Check coordinates validity
    guard (-180.0...180.0).contains(lng) && (-90.0...90.0).contains(lat) else {
      throw TZFError.invalidCoordinates
    }

    // Try each zoom level from aggZoom to idxZoom
    for zoom in aggZoom...idxZoom {
      let (x, y) = lngLatToTile(lng: lng, lat: lat, zoom: zoom)
      let tileKey = "\(zoom):\(x):\(y)"

      // Look up in the cache
      if let tzNames = tileCache[tileKey], !tzNames.isEmpty {
        return tzNames  // Already sorted during initialization
      }
    }

    throw TZFError.noTimezoneFound
  }
}

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

/// A timezone finder that uses full polygon data for accurate timezone lookups.
///
/// This finder loads the complete timezone boundary data and performs point-in-polygon
/// tests to determine which timezone(s) a coordinate belongs to. While more accurate
/// than the PreindexFinder, it uses simplified polygon data for better performance.
///
/// Important Notes:
/// - The polygon data has been pre-simplified to reduce complexity
/// - Accuracy is balanced with performance considerations
/// - Near timezone boundaries, multiple results may be returned due to simplification
///
/// Features:
/// - Full polygon boundary support (with simplified geometries)
/// - Support for timezone holes (enclaves)
/// - Fallback mechanism for coordinates near timezone boundaries
/// - Efficient point-in-polygon testing with simplified data
public class Finder: F {
  private let timezones: Tzf_V1_Timezones
  private struct ProcessedTimezone {
    let name: String
    let polygons: [Polygon]
  }
  private let processedTimezones: [ProcessedTimezone]

  public init() throws {
    let bundle: Bundle = Bundle.module

    guard
      let reduceURL = bundle.url(
        forResource: "combined-with-oceans.reduce", withExtension: "bin")
    else {
      throw TZFError.dataError
    }

    let reduceData = try Data(contentsOf: reduceURL)
    self.timezones = try Tzf_V1_Timezones(serializedBytes: [UInt8](reduceData))

    // Pre-process all polygons during initialization
    var processed: [ProcessedTimezone] = []
    for timezone in timezones.timezones {
      var processedPolygons: [Polygon] = []

      for polygon in timezone.polygons {
        let exterior = polygon.points.map { Point(x: Double($0.lng), y: Double($0.lat)) }
        let holes = polygon.holes.map { hole in
          hole.points.map { Point(x: Double($0.lng), y: Double($0.lat)) }
        }
        let poly = Polygon.new(exterior: exterior, holes: holes)
        processedPolygons.append(poly)
      }

      processed.append(ProcessedTimezone(name: timezone.name, polygons: processedPolygons))
    }
    self.processedTimezones = processed
  }

  public func dataVersion() -> String {
    return timezones.version
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    // return first result from getTimezones
    return try getTimezones(lng: lng, lat: lat).first!
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    let point = Point(x: lng, y: lat)
    var results: [String] = []

    for timezone in processedTimezones {
      for polygon in timezone.polygons {
        if polygon.containsPoint(point) {
          results.append(timezone.name)
          break  // Found a match in this timezone, move to next
        }
      }
    }

    if results.isEmpty {
      let lngShifts = [0.0, -0.01, 0.01, -0.02, 0.02]
      let latShifts = [0.0, -0.01, 0.01, -0.02, 0.02]
      for lngShift in lngShifts {
        for latShift in latShifts {
          let shiftedPoint = Point(x: lng + lngShift, y: lat + latShift)
          for timezone in processedTimezones {
            for polygon in timezone.polygons {
              if polygon.containsPoint(shiftedPoint) {
                results.append(timezone.name)
                break  // Found a match in this timezone, move to next
              }
            }
          }
        }
      }
    }

    if results.isEmpty {
      throw FinderError.noTimezoneFound
    }

    // sort results by name
    results.sort()

    return results
  }
}

/// Represents errors specific to the Finder implementation.
public enum FinderError: Error {
  case noTimezoneFound
}

/// The default finder implementation that combines both PreindexFinder and Finder
/// for optimal performance and accuracy.
///
/// This finder first attempts to use the PreindexFinder for fast lookups using
/// pre-indexed tiles. If that fails, it falls back to the more accurate but slower
/// Finder implementation that uses full polygon data.
public class DefaultFinder: F {
  private let preindexFinder: PreindexFinder
  private let reduceFinder: Finder

  public init() throws {
    self.preindexFinder = try PreindexFinder()
    self.reduceFinder = try Finder()
  }

  public func dataVersion() -> String {
    return "\(preindexFinder.dataVersion())/\(reduceFinder.dataVersion())"
  }

  public func getTimezone(lng: Double, lat: Double) throws -> String {
    do {
      // Try preindex finder first
      return try preindexFinder.getTimezone(lng: lng, lat: lat)
    } catch {
      // If preindex finder fails, try reduce finder
      return try reduceFinder.getTimezone(lng: lng, lat: lat)
    }
  }

  public func getTimezones(lng: Double, lat: Double) throws -> [String] {
    do {
      // Try preindex finder first
      return try preindexFinder.getTimezones(lng: lng, lat: lat)
    } catch {
      // If preindex finder fails, try reduce finder
      return try reduceFinder.getTimezones(lng: lng, lat: lat)
    }
  }
}
