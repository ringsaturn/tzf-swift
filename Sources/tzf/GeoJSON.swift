import Foundation
import geometry

public typealias GeoJSONPolygonCoordinates = [[[Double]]]
public typealias GeoJSONMultiPolygonCoordinates = [GeoJSONPolygonCoordinates]

/// GeoJSON geometry for timezone boundaries.
public struct GeoJSONGeometry: Codable, Sendable, Equatable {
  public let type: String
  public let coordinates: GeoJSONMultiPolygonCoordinates

  public init(type: String, coordinates: GeoJSONMultiPolygonCoordinates) {
    self.type = type
    self.coordinates = coordinates
  }
}

/// GeoJSON properties that carry timezone name.
public struct GeoJSONProperties: Codable, Sendable, Equatable {
  public let tzid: String

  public init(tzid: String) {
    self.tzid = tzid
  }
}

/// GeoJSON feature for one timezone.
public struct GeoJSONFeature: Codable, Sendable, Equatable {
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
public struct GeoJSONFeatureCollection: Codable, Sendable, Equatable {
  public let type: String
  public let features: [GeoJSONFeature]

  public init(type: String, features: [GeoJSONFeature]) {
    self.type = type
    self.features = features
  }

  public func toJSONString(pretty: Bool = false) throws -> String {
    let encoder = JSONEncoder()
    if pretty {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    } else {
      encoder.outputFormatting = [.sortedKeys]
    }
    let data = try encoder.encode(self)
    guard let output = String(data: data, encoding: .utf8) else {
      throw TZFError.dataError
    }
    return output
  }
}

// MARK: - Builders

enum GeoJSON {
  static func collection(_ features: [GeoJSONFeature]) -> GeoJSONFeatureCollection {
    GeoJSONFeatureCollection(type: "FeatureCollection", features: features)
  }

  static func feature(name: String, coordinates: GeoJSONMultiPolygonCoordinates) -> GeoJSONFeature {
    GeoJSONFeature(
      type: "Feature",
      properties: GeoJSONProperties(tzid: name),
      geometry: GeoJSONGeometry(type: "MultiPolygon", coordinates: coordinates))
  }

  /// A closed GeoJSON ring (first coordinate repeated last) from an open
  /// 1e5-scaled ring.
  static func closedRing(_ ring: [I32Point]) -> [[Double]] {
    var coords = [[Double]]()
    coords.reserveCapacity(ring.count + 1)
    for p in ring {
      coords.append([Double(p.x) / i32Scale, Double(p.y) / i32Scale])
    }
    if let first = coords.first {
      coords.append(first)
    }
    return coords
  }

  static func feature(name: String, polygons: [ExpandedPolygon]) -> GeoJSONFeature {
    let coordinates = polygons.map { poly -> GeoJSONPolygonCoordinates in
      var rings: GeoJSONPolygonCoordinates = []
      rings.reserveCapacity(poly.holes.count + 1)
      rings.append(closedRing(poly.exterior))
      for hole in poly.holes {
        rings.append(closedRing(hole))
      }
      return rings
    }
    return feature(name: name, coordinates: coordinates)
  }

  static func feature(name: String, polygons: [I32Polygon]) -> GeoJSONFeature {
    let coordinates = polygons.map { poly -> GeoJSONPolygonCoordinates in
      var rings: GeoJSONPolygonCoordinates = []
      rings.reserveCapacity(poly.holes.count + 1)
      rings.append(closedRing(poly.exterior))
      for hole in poly.holes {
        rings.append(closedRing(hole))
      }
      return rings
    }
    return feature(name: name, coordinates: coordinates)
  }

  /// One Feature whose MultiPolygon holds each FUZZY tile's bounding
  /// rectangle as one closed ring.
  static func feature(name: String, tileKeys: [UInt64]) -> GeoJSONFeature {
    feature(name: name, coordinates: tileKeys.map { [TileID(raw: $0).polygon()] })
  }
}
