/// Point-in-polygon geometry for tzf, ported from tzf's `internal/geom`
/// package (itself derived from [tidwall/geojson](https://github.com/tidwall/geojson),
/// MIT licence).
///
/// Rings are stored as 1e5-scaled `Int32` coordinates (the `.tzb` storage
/// domain) and queried in that same scaled space with `Double` arithmetic, so
/// results are bit-identical to the Go and Rust implementations over the same
/// data.
import Foundation

/// A point in query space (`Double`). For scaled polygons this is the
/// 1e5-scaled domain, not degrees.
public struct Point: Sendable, Equatable {
  public var x: Double
  public var y: Double

  @inlinable
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A 1e5-scaled integer coordinate, the storage form of every ring.
public struct I32Point: Sendable, Equatable, Hashable {
  public var x: Int32
  public var y: Int32

  @inlinable
  public init(x: Int32, y: Int32) {
    self.x = x
    self.y = y
  }

  @inlinable
  public var asPoint: Point { Point(x: Double(x), y: Double(y)) }
}

/// The scale between degrees and the integer storage domain.
public let i32Scale: Double = 1e5

/// Outcome of testing one segment against a horizontal ray.
public struct RaycastResult: Sendable {
  /// The ray crosses the segment (point is to the left of the crossing).
  public let inside: Bool
  /// The point lies directly on the segment.
  public let on: Bool

  @inlinable
  public init(inside: Bool, on: Bool) {
    self.inside = inside
    self.on = on
  }
}

/// Tests whether a leftward horizontal ray from `p` crosses segment `(a, b)`.
///
/// Direct port of the ray-casting function in tidwall/geojson, shared with
/// tzf (Go) and tzf-rs (Rust) so every lookup mechanism has one boundary
/// behaviour:
///
/// - Horizontal and vertical segments are handled explicitly.
/// - A point landing exactly on a vertex has `p.y` nudged with `nextUp` so
///   the vertex is counted at most once.
/// - Collinear points are reported as `on` rather than `inside`.
@inlinable
public func raycastSeg(_ a: Point, _ b: Point, _ p: Point) -> RaycastResult {
  var py = p.y

  // Quick Y-range rejection.
  if a.y < b.y {
    if py < a.y || py > b.y {
      return RaycastResult(inside: false, on: false)
    }
  } else if a.y > b.y {
    if py < b.y || py > a.y {
      return RaycastResult(inside: false, on: false)
    }
  }

  // Detect if p lies on the segment before the raycast nudge.
  if a.y == b.y {
    // horizontal segment
    if a.x == b.x {
      // degenerate (single point)
      if p.x == a.x && py == a.y {
        return RaycastResult(inside: false, on: true)
      }
      return RaycastResult(inside: false, on: false)
    }
    if py == b.y {
      if a.x < b.x {
        if p.x >= a.x && p.x <= b.x {
          return RaycastResult(inside: false, on: true)
        }
      } else if p.x >= b.x && p.x <= a.x {
        return RaycastResult(inside: false, on: true)
      }
    }
  }
  if a.x == b.x && p.x == b.x {
    // vertical segment
    if a.y < b.y {
      if py >= a.y && py <= b.y {
        return RaycastResult(inside: false, on: true)
      }
    } else if py >= b.y && py <= a.y {
      return RaycastResult(inside: false, on: true)
    }
  }
  // General collinearity check. Division by zero yields Inf/NaN; NaN != NaN
  // and Inf != finite, so the comparison safely returns false in those cases.
  if (p.x - a.x) / (b.x - a.x) == (py - a.y) / (b.y - a.y) {
    return RaycastResult(inside: false, on: true)
  }

  // Nudge py off any vertex to avoid double-counting shared polygon vertices.
  while py == a.y || py == b.y {
    py = py.nextUp
  }

  // Re-check Y bounds after nudge.
  if a.y < b.y {
    if py < a.y || py > b.y {
      return RaycastResult(inside: false, on: false)
    }
  } else if py < b.y || py > a.y {
    return RaycastResult(inside: false, on: false)
  }

  // X-axis shortcuts: if p.x is clearly to the right or left of both
  // endpoints, the crossing result is trivial.
  if a.x > b.x {
    if p.x >= a.x {
      return RaycastResult(inside: false, on: false)
    }
    if p.x <= b.x {
      return RaycastResult(inside: true, on: false)
    }
  } else {
    if p.x >= b.x {
      return RaycastResult(inside: false, on: false)
    }
    if p.x <= a.x {
      return RaycastResult(inside: true, on: false)
    }
  }

  // Slope comparison to determine which side of the segment p lies on.
  if a.y < b.y {
    if (py - a.y) / (p.x - a.x) >= (b.y - a.y) / (b.x - a.x) {
      return RaycastResult(inside: true, on: false)
    }
  } else if (py - b.y) / (p.x - b.x) >= (a.y - b.y) / (a.x - b.x) {
    return RaycastResult(inside: true, on: false)
  }
  return RaycastResult(inside: false, on: false)
}

// MARK: - YStripes index

/// Minimum number of stripes, and the minimum ring segment count below which
/// no index is built (linear scan is fast enough). Matches Go `yStripesMin`.
@usableFromInline let yStripesMin = 32

/// Partitions the segments of one open ring into horizontal stripes so a PIP
/// query for latitude `y` only examines the segments in the stripe that
/// contains `y`. Lives in the ring's storage space (1e5-scaled).
///
/// Per-segment Y ranges are not stored; candidate filtering recomputes them
/// from the ring endpoints, which the raycast fetches anyway.
@usableFromInline
struct YStripesIndex: Sendable {
  @usableFromInline let minY: Double
  /// `maxY - minY`.
  @usableFromInline let height: Double
  /// One `(start, count)` per stripe, referencing into `indexes`.
  @usableFromInline let stripes: [(start: UInt32, count: UInt32)]
  /// Segment indices packed stripe by stripe.
  @usableFromInline let indexes: [UInt32]

  /// Builds the index for an open ring of `n` points (`n` wrap-around
  /// segments). Returns `nil` when the ring has fewer than 2 points or a zero
  /// Y span.
  init?(ring: [I32Point]) {
    let n = ring.count
    guard n >= 2 else { return nil }

    var yRanges = [(Double, Double)](repeating: (0, 0), count: n)
    var minY = Double(ring[0].y)
    var maxY = minY
    for i in 0..<n {
      let j = i + 1 == n ? 0 : i + 1
      let ay = Double(ring[i].y)
      let by = Double(ring[j].y)
      let lo = ay <= by ? ay : by
      let hi = ay <= by ? by : ay
      yRanges[i] = (lo, hi)
      if lo < minY { minY = lo }
      if hi > maxY { maxY = hi }
    }

    let height = maxY - minY
    guard height != 0 else { return nil }

    let stripeCount = YStripesIndex.calcStripeCount(ring: ring)

    var counts = [Int](repeating: 0, count: stripeCount)
    for i in 0..<n {
      let (lo, hi) = YStripesIndex.segStripeRange(
        yRanges[i].0, yRanges[i].1, minY, height, stripeCount)
      for s in lo...hi { counts[s] += 1 }
    }

    var stripes = [(start: UInt32, count: UInt32)](repeating: (0, 0), count: stripeCount)
    var starts = [Int](repeating: 0, count: stripeCount)
    var total = 0
    for s in 0..<stripeCount {
      starts[s] = total
      stripes[s].start = UInt32(total)
      total += counts[s]
    }

    var indexes = [UInt32](repeating: 0, count: total)
    for i in 0..<n {
      let (lo, hi) = YStripesIndex.segStripeRange(
        yRanges[i].0, yRanges[i].1, minY, height, stripeCount)
      for s in lo...hi {
        let pos = starts[s] + Int(stripes[s].count)
        indexes[pos] = UInt32(i)
        stripes[s].count += 1
      }
    }

    self.minY = minY
    self.height = height
    self.stripes = stripes
    self.indexes = indexes
  }

  /// Number of stripes for a ring, from the isoperimetric quotient
  /// (circularity): circular rings get more stripes, elongated rings fewer.
  private static func calcStripeCount(ring: [I32Point]) -> Int {
    let n = ring.count
    var area = 0.0
    var perim = 0.0
    for i in 0..<n {
      let j = i + 1 == n ? 0 : i + 1
      let ax = Double(ring[i].x)
      let ay = Double(ring[i].y)
      let bx = Double(ring[j].x)
      let by = Double(ring[j].y)
      area += ax * by - bx * ay
      let dx = bx - ax
      let dy = by - ay
      perim += (dx * dx + dy * dy).squareRoot()
    }
    area = abs(area) * 0.5
    let score = perim > 0 ? (area * .pi * 4) / (perim * perim) : 0.0
    let count = Int((Double(n) * score).rounded(.down))
    return count < yStripesMin ? yStripesMin : count
  }

  @inlinable @inline(__always)
  static func clampStripe(_ i: Int, _ last: Int) -> Int {
    if i < 0 { return 0 }
    if i > last { return last }
    return i
  }

  /// Maps a segment's `[segMinY, segMaxY]` to the inclusive stripe range.
  private static func segStripeRange(
    _ segMinY: Double, _ segMaxY: Double,
    _ minY: Double, _ height: Double, _ count: Int
  ) -> (Int, Int) {
    guard count > 1 && height != 0 else { return (0, 0) }
    let last = count - 1
    let lo = clampStripe(Int(((segMinY - minY) / height * Double(count)).rounded(.down)), last)
    let hi = clampStripe(Int(((segMaxY - minY) / height * Double(count)).rounded(.down)), last)
    return (lo, hi)
  }

  @inlinable @inline(__always)
  func pointStripe(_ y: Double) -> Int {
    YStripesIndex.clampStripe(
      Int(((y - minY) / height * Double(stripes.count)).rounded(.down)), stripes.count - 1)
  }
}

// MARK: - Ring containment

/// Even-odd ray-casting containment for an open ring. `p` must be in the
/// ring's storage space. A point on the ring boundary returns `allowOnEdge`.
@usableFromInline @inlinable
func ringContainsPoint(
  _ ring: [I32Point], _ idx: YStripesIndex?, _ p: Point, _ allowOnEdge: Bool
) -> Bool {
  let n = ring.count
  guard n >= 3 else { return false }

  var inside = false

  if let idx = idx {
    // Indexed path: iterate only the stripe containing p.y.
    if p.y < idx.minY || p.y > idx.minY + idx.height { return false }
    let stripe = idx.stripes[idx.pointStripe(p.y)]
    let start = Int(stripe.start)
    let end = start + Int(stripe.count)
    return ring.withUnsafeBufferPointer { r in
      idx.indexes.withUnsafeBufferPointer { indexes in
        for k in start..<end {
          let seg = Int(indexes[k])
          let next = seg + 1 == n ? 0 : seg + 1
          var ay = Double(r[seg].y)
          var by = Double(r[next].y)
          if by < ay { swap(&ay, &by) }
          if p.y >= ay && p.y <= by {
            let res = raycastSeg(r[seg].asPoint, r[next].asPoint, p)
            if res.on {
              return allowOnEdge
            }
            if res.inside { inside.toggle() }
          }
        }
        return inside
      }
    }
  }

  // Linear fallback for small rings.
  return ring.withUnsafeBufferPointer { r in
    for i in 0..<n {
      let j = i + 1 == n ? 0 : i + 1
      let res = raycastSeg(r[i].asPoint, r[j].asPoint, p)
      if res.on {
        return allowOnEdge
      }
      if res.inside { inside.toggle() }
    }
    return inside
  }
}

// MARK: - Polygon

/// A polygon stored as 1e5-scaled `Int32` open rings (no closing vertex),
/// with a YStripes index on every ring of at least `yStripesMin` points.
public struct I32Polygon: Sendable {
  /// Exterior ring, open form.
  public let exterior: [I32Point]
  /// Hole rings, open form.
  public let holes: [[I32Point]]
  /// Storage-space bounding box of the exterior.
  public let minX: Int32
  public let minY: Int32
  public let maxX: Int32
  public let maxY: Int32
  @usableFromInline let extIdx: YStripesIndex?
  @usableFromInline let holeIdxs: [YStripesIndex?]

  /// Creates a polygon from open or closed rings; a closing duplicate point
  /// is stripped. `exterior` must not be empty.
  public init(exterior: [I32Point], holes: [[I32Point]]) {
    let ext = I32Polygon.openRing(exterior)
    let hls = holes.map(I32Polygon.openRing)
    precondition(!ext.isEmpty, "exterior ring cannot be empty")

    var minX = ext[0].x
    var minY = ext[0].y
    var maxX = ext[0].x
    var maxY = ext[0].y
    for p in ext {
      if p.x < minX { minX = p.x }
      if p.y < minY { minY = p.y }
      if p.x > maxX { maxX = p.x }
      if p.y > maxY { maxY = p.y }
    }

    self.exterior = ext
    self.holes = hls
    self.minX = minX
    self.minY = minY
    self.maxX = maxX
    self.maxY = maxY
    self.extIdx = ext.count >= yStripesMin ? YStripesIndex(ring: ext) : nil
    self.holeIdxs = hls.map { $0.count >= yStripesMin ? YStripesIndex(ring: $0) : nil }
  }

  private static func openRing(_ pts: [I32Point]) -> [I32Point] {
    let n = pts.count
    if n >= 2 && pts[0] == pts[n - 1] {
      return Array(pts[..<(n - 1)])
    }
    return pts
  }

  /// Whether the scaled-space point `sp` lies inside the polygon: inside the
  /// exterior ring and outside every hole. `allowOnEdge` applies to the
  /// exterior ring only; a point on a hole's boundary counts as not in the
  /// hole, i.e. inside the polygon under either rule.
  @inlinable
  public func containsScaledPoint(_ sp: Point, allowOnEdge: Bool) -> Bool {
    if sp.x < Double(minX) || sp.x > Double(maxX) || sp.y < Double(minY) || sp.y > Double(maxY) {
      return false
    }
    if !ringContainsPoint(exterior, extIdx, sp, allowOnEdge) {
      return false
    }
    for i in 0..<holes.count {
      if ringContainsPoint(holes[i], holeIdxs[i], sp, false) {
        return false
      }
    }
    return true
  }

  /// Whether the degree-space point lies strictly inside the polygon.
  @inlinable
  public func containsPoint(lng: Double, lat: Double) -> Bool {
    containsScaledPoint(Point(x: lng * i32Scale, y: lat * i32Scale), allowOnEdge: false)
  }

  /// Like `containsPoint`, but a point on the exterior boundary returns true.
  /// For polygons that tile a plane this makes a shared border belong to
  /// every polygon touching it, so no query falls through a crack.
  @inlinable
  public func containsPointAllowOnEdge(lng: Double, lat: Double) -> Bool {
    containsScaledPoint(Point(x: lng * i32Scale, y: lat * i32Scale), allowOnEdge: true)
  }
}
