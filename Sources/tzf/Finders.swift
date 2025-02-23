import Foundation
import SwiftProtobuf
import geometry

public protocol F {
    func dataVersion() -> String
    func getTimezone(lng: Double, lat: Double) throws -> String
    func getTimezones(lng: Double, lat: Double) throws -> [String]
}

public struct PreindexFinder: F {
    private let preindexData: Tzf_V1_PreindexTimezones
    private let idxZoom: Int32
    private let aggZoom: Int32
    private let tileCache: [String: [String]]

    public init() throws {
        let bundle = Bundle.module

        guard
            let preindexURL = bundle.url(
                forResource: "combined-with-oceans.reduce.preindex", withExtension: "pb")
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
                return tzNames // Already sorted during initialization
            }
        }

        throw TZFError.noTimezoneFound
    }
}

public enum TZFError: Error {
    case invalidCoordinates
    case noTimezoneFound
    case dataError
}

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
                forResource: "combined-with-oceans.reduce", withExtension: "pb")
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
        let point = Point(x: lng, y: lat)

        for timezone in processedTimezones {
            for polygon in timezone.polygons {
                if polygon.containsPoint(point) {
                    return timezone.name
                }
            }
        }

        let lngShifts = [0.0, -0.01, 0.01, -0.02, 0.02]
        let latShifts = [0.0, -0.01, 0.01, -0.02, 0.02]
        for lngShift in lngShifts {
            for latShift in latShifts {
                let shiftedPoint = Point(x: lng + lngShift, y: lat + latShift)
                for timezone in processedTimezones {
                    for polygon in timezone.polygons {
                        if polygon.containsPoint(shiftedPoint) {
                            return timezone.name
                        }
                    }
                }
            }
        }

        throw FinderError.noTimezoneFound
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
            throw FinderError.noTimezoneFound
        }

        return results
    }
}

public enum FinderError: Error {
    case noTimezoneFound
}

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
