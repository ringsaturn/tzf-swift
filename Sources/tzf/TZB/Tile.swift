/// Slippy-map tile arithmetic, ported from the Go `internal/geom` package so
/// FUZZY lookups compute bit-identical tile keys to the preindex encoder.
import Foundation

/// Returns the slippy-map tile column (x) and row (y) for (lng, lat) at the
/// given zoom level, using the Web Mercator projection (OSM convention).
@inline(__always)
func tileXY(lng: Double, lat: Double, zoom: UInt32) -> (x: UInt32, y: UInt32) {
  let n = Double(UInt32(1) << zoom)
  // Go/Rust truncate the float toward zero (Rust saturating at 0); the
  // caller guarantees lng ∈ [-180, 180], so the value is in [0, n].
  let xr = (lng / 360.0 + 0.5) * n
  let x = xr <= 0 ? 0 : UInt32(xr)
  let y: UInt32
  if lat > 85.0511 {
    y = 0
  } else if lat < -85.0511 {
    y = UInt32(n) - 1
  } else {
    let siny = sin(lat * .pi / 180.0)
    let raw = (0.5 - log((1.0 + siny) / (1.0 - siny)) / (4.0 * .pi)) * n
    // Rust's `as u32` saturates; at exactly ±85.0511 the formula can land a
    // hair below zero, which Swift would otherwise trap on.
    y = raw <= 0 ? 0 : UInt32(raw)
  }
  return (x, y)
}

/// Packs (x, y, z) into a single key.
/// Layout: bits 56-63 = zoom (0-255), bits 28-55 = x, bits 0-27 = y.
/// This covers all OSM zoom levels (0-28) without collision.
struct TileID: Hashable, Sendable {
  let raw: UInt64

  @inline(__always)
  init(raw: UInt64) {
    self.raw = raw
  }

  @inline(__always)
  init(lng: Double, lat: Double, zoom: UInt32) {
    let (x, y) = tileXY(lng: lng, lat: lat, zoom: zoom)
    self.init(x: x, y: y, z: UInt8(zoom))
  }

  @inline(__always)
  init(x: UInt32, y: UInt32, z: UInt8) {
    raw = UInt64(z) << 56 | UInt64(x) << 28 | UInt64(y)
  }

  @inline(__always)
  var xyz: (x: UInt32, y: UInt32, z: UInt8) {
    (
      UInt32(truncatingIfNeeded: raw >> 28) & 0x0FFF_FFFF,
      UInt32(truncatingIfNeeded: raw) & 0x0FFF_FFFF,
      UInt8(truncatingIfNeeded: raw >> 56)
    )
  }

  /// The tile at a coarser zoom: right-shift the high-zoom tile coordinates
  /// instead of repeating the transcendental math.
  @inline(__always)
  func shift(_ shift: UInt8) -> TileID {
    let (x, y, z) = xyz
    if shift > z {
      return TileID(raw: 0)
    }
    return TileID(x: x >> UInt32(shift), y: y >> UInt32(shift), z: z - shift)
  }

  /// The tile's bounding rectangle as a closed GeoJSON ring — five
  /// counterclockwise `[lng, lat]` points, first repeated last. Port of Go
  /// `geom.TileID.Polygon`.
  func polygon() -> [[Double]] {
    let (x, y, z) = xyz
    let n = Double(UInt32(1) << UInt32(z))

    let lngMin = Double(x) / n * 360.0 - 180.0
    let lngMax = Double(x + 1) / n * 360.0 - 180.0

    let latMax = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n))) * 180.0 / .pi
    let latMin = atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n))) * 180.0 / .pi

    return [
      [lngMin, latMin],
      [lngMax, latMin],
      [lngMax, latMax],
      [lngMin, latMax],
      [lngMin, latMin],
    ]
  }
}
