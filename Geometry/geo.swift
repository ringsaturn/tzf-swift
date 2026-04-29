/// Rewrite parts of [tidwall/geometry](https://github.com/tidwall/geometry) in Swift.
import Foundation

public struct Point {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct Rect {
  public let min: Point
  public let max: Point

  public init(min: Point, max: Point) {
    self.min = min
    self.max = max
  }

  public func containsPoint(_ p: Point) -> Bool {
    return p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y
  }

  public func intersectsRect(_ other: Rect) -> Bool {
    if min.y > other.max.y || max.y < other.min.y {
      return false
    }
    if min.x > other.max.x || max.x < other.min.x {
      return false
    }
    return true
  }

  public func nw() -> Point {
    return Point(x: min.x, y: max.y)
  }

  public func sw() -> Point {
    return Point(x: min.x, y: min.y)
  }

  public func se() -> Point {
    return Point(x: max.x, y: min.y)
  }

  public func ne() -> Point {
    return Point(x: max.x, y: max.y)
  }

  public func south() -> Segment {
    return Segment(a: sw(), b: se())
  }

  public func east() -> Segment {
    return Segment(a: se(), b: ne())
  }

  public func north() -> Segment {
    return Segment(a: ne(), b: nw())
  }

  public func west() -> Segment {
    return Segment(a: nw(), b: sw())
  }

  public func segmentAt(_ index: Int) -> Segment {
    switch index {
    case 0: return south()
    case 1: return east()
    case 2: return north()
    case 3: return west()
    default: return south()  // TODO: Handle error case
    }
  }
}

public struct Segment {
  public let a: Point
  public let b: Point

  public init(a: Point, b: Point) {
    self.a = a
    self.b = b
  }

  public func rect() -> Rect {
    var minX = a.x
    var minY = a.y
    var maxX = b.x
    var maxY = b.y

    if minX > maxX {
      swap(&minX, &maxX)
    }

    if minY > maxY {
      swap(&minY, &maxY)
    }

    return Rect(
      min: Point(x: minX, y: minY),
      max: Point(x: maxX, y: maxY)
    )
  }
}

public struct RaycastResult {
  public let inside: Bool  // point on the left
  public let on: Bool  // point is directly on top of

  public init(inside: Bool, on: Bool) {
    self.inside = inside
    self.on = on
  }
}

public func segmentAtForVecPoint(_ exterior: [Point], _ index: Int) -> Segment {
  let segA = exterior[index]
  var segBIndex = index
  if segBIndex == exterior.count - 1 {
    segBIndex = 0
  } else {
    segBIndex += 1
  }
  let segB = exterior[segBIndex]
  return Segment(a: segA, b: segB)
}

public func raycast(_ seg: Segment, _ point: Point) -> RaycastResult {
  var py = point.y
  let px = point.x
  let a = seg.a
  let b = seg.b

  // make sure that the point is inside the segment bounds
  if a.y < b.y && (py < a.y || py > b.y) {
    return RaycastResult(inside: false, on: false)
  } else if a.y > b.y && (py < b.y || py > a.y) {
    return RaycastResult(inside: false, on: false)
  }

  // test if point is in on the segment
  if a.y == b.y {
    if a.x == b.x {
      if px == a.x && py == a.y {
        return RaycastResult(inside: false, on: true)
      }
      return RaycastResult(inside: false, on: false)
    }
    if py == b.y {
      // horizontal segment
      // check if the point in on the line
      if a.x < b.x {
        if px >= a.x && px <= b.x {
          return RaycastResult(inside: false, on: true)
        }
      } else {
        if px >= b.x && px <= a.x {
          return RaycastResult(inside: false, on: true)
        }
      }
    }
  }

  if a.x == b.x && px == b.x {
    // vertical segment
    // check if the point in on the line
    if a.y < b.y {
      if py >= a.y && py <= b.y {
        return RaycastResult(inside: false, on: true)
      }
    } else {
      if py >= b.y && py <= a.y {
        return RaycastResult(inside: false, on: true)
      }
    }
  }

  // Check if point lies on the line segment
  if abs(b.x - a.x) > Double.ulpOfOne {  // Avoid division by zero
    let slope = (b.y - a.y) / (b.x - a.x)
    let yIntercept = a.y - slope * a.x
    let expectedY = slope * px + yIntercept
    if abs(expectedY - py) < Double.ulpOfOne {
      return RaycastResult(inside: false, on: true)
    }
  }

  // do the actual raycast here.
  while py == a.y || py == b.y {
    py = py.nextUp
  }

  if a.y < b.y {
    if py < a.y || py > b.y {
      return RaycastResult(inside: false, on: false)
    }
  } else {
    if py < b.y || py > a.y {
      return RaycastResult(inside: false, on: false)
    }
  }

  if a.x > b.x {
    if px >= a.x {
      return RaycastResult(inside: false, on: false)
    }
    if px <= b.x {
      return RaycastResult(inside: true, on: false)
    }
  } else {
    if px >= b.x {
      return RaycastResult(inside: false, on: false)
    }
    if px <= a.x {
      return RaycastResult(inside: true, on: false)
    }
  }

  let dx = b.x - a.x
  let dy = b.y - a.y

  if abs(dx) > Double.ulpOfOne {  // Avoid division by zero
    if a.y < b.y {
      let slope = (py - a.y) / (px - a.x)
      let slopeSegment = dy / dx
      return RaycastResult(inside: slope >= slopeSegment, on: false)
    } else {
      let slope = (py - b.y) / (px - b.x)
      let slopeSegment = (a.y - b.y) / (a.x - b.x)
      return RaycastResult(inside: slope >= slopeSegment, on: false)
    }
  }

  return RaycastResult(inside: false, on: false)
}

public func ringsContainsPoint(_ ring: [Point], _ point: Point, _ allowOnEdge: Bool) -> Bool {
  let rect = Rect(
    min: Point(x: -Double.infinity, y: point.y),
    max: Point(x: Double.infinity, y: point.y)
  )

  var inside = false
  let n = ring.count - 1

  for i in 0..<n {
    let seg = segmentAtForVecPoint(ring, i)

    if seg.rect().intersectsRect(rect) {
      let res = raycast(seg, point)
      if res.on {
        inside = allowOnEdge
        break
      }
      if res.inside {
        inside.toggle()
      }
    }
  }
  return inside
}

// MARK: - YStripes index

/// Minimum segment count for a ring to get a YStripes index.
/// Rings smaller than this are cheaper to scan linearly.
private let yStripesMinSegments = 32

/// Partitions a ring's segments into horizontal stripes so that a PIP query
/// for latitude y only needs to examine the segments in the one stripe that
/// contains y.  Reduces average PIP cost from O(n) to O(n/k).
///
/// Port of the YStripes index from
/// [tzf](https://github.com/ringsaturn/tzf/blob/main/internal/geom/ystripes.go).
struct YStripesIndex {
  /// Bottom of the ring's Y range.
  let minY: Double
  /// Height of the Y range (maxY − minY).
  let height: Double
  /// One (start, count) pair per stripe, referencing into `indexes`.
  let stripes: [(start: Int, count: Int)]
  /// Segment indices packed stripe-by-stripe.
  let indexes: [Int]
  /// Per-segment [minY, maxY] bounding box, indexed by segment number.
  let yRanges: [(Double, Double)]

  /// Builds a YStripes index for `ring`.
  ///
  /// `ring` is a **closed** ring (first == last point), so the number of
  /// segments is `ring.count - 1`.  Returns `nil` when the ring has fewer
  /// than 2 segments or a zero Y span.
  init?(ring: [Point]) {
    let n = ring.count - 1  // number of segments
    guard n >= 2 else { return nil }

    // Compute per-segment Y bounding boxes and the global Y range.
    var yRanges = [(Double, Double)](repeating: (0.0, 0.0), count: n)
    var minY = Double.infinity
    var maxY = -Double.infinity
    for i in 0..<n {
      let ay = ring[i].y, by = ring[i + 1].y
      let lo = min(ay, by), hi = max(ay, by)
      yRanges[i] = (lo, hi)
      if lo < minY { minY = lo }
      if hi > maxY { maxY = hi }
    }

    let height = maxY - minY
    guard height > 0 else { return nil }

    let stripeCount = YStripesIndex.calcStripeCount(ring: ring, n: n)
    var stripes = [(start: Int, count: Int)](repeating: (0, 0), count: stripeCount)

    // First pass: count how many segment references each stripe needs.
    for i in 0..<n {
      let (lo, hi) = YStripesIndex.segStripeRange(
        yRanges[i].0, yRanges[i].1, minY, height, stripeCount)
      for s in lo...hi { stripes[s].count += 1 }
    }

    // Assign start offsets; reset count to use as fill cursor.
    var fillPos = [Int](repeating: 0, count: stripeCount)
    var total = 0
    for s in 0..<stripeCount {
      fillPos[s] = total
      stripes[s] = (start: total, count: 0)
      total += stripes[s].count  // still 0 after reset — use fillPos instead
    }
    // Recount to get the actual totals for filling.
    var counts = [Int](repeating: 0, count: stripeCount)
    for i in 0..<n {
      let (lo, hi) = YStripesIndex.segStripeRange(
        yRanges[i].0, yRanges[i].1, minY, height, stripeCount)
      for s in lo...hi { counts[s] += 1 }
    }
    total = 0
    for s in 0..<stripeCount {
      fillPos[s] = total
      stripes[s] = (start: total, count: counts[s])
      total += counts[s]
    }

    // Second pass: fill the indexes slice.
    var indexes = [Int](repeating: 0, count: total)
    var cursors = [Int](repeating: 0, count: stripeCount)
    for i in 0..<n {
      let (lo, hi) = YStripesIndex.segStripeRange(
        yRanges[i].0, yRanges[i].1, minY, height, stripeCount)
      for s in lo...hi {
        indexes[stripes[s].start + cursors[s]] = i
        cursors[s] += 1
      }
    }

    self.minY = minY
    self.height = height
    self.stripes = stripes
    self.indexes = indexes
    self.yRanges = yRanges
  }

  /// Calls `fn(segmentIndex)` for every segment whose Y range includes `y`.
  /// Stops when `fn` returns `false`.  No allocation.
  func forEachCandidate(y: Double, _ fn: (Int) -> Bool) {
    guard y >= minY && y <= minY + height else { return }
    let count = stripes.count
    let s = min(Int((y - minY) / height * Double(count)), count - 1)
    let stripe = stripes[s]
    for k in stripe.start..<(stripe.start + stripe.count) {
      let seg = indexes[k]
      if y >= yRanges[seg].0 && y <= yRanges[seg].1 {
        if !fn(seg) { return }
      }
    }
  }

  /// Number of horizontal stripes to use for a ring.
  ///
  /// Uses the isoperimetric quotient (circularity score) so that circular
  /// rings get more stripes and elongated rings get fewer.
  private static func calcStripeCount(ring: [Point], n: Int) -> Int {
    var area = 0.0
    var perim = 0.0
    for i in 0..<n {
      let a = ring[i], b = ring[i + 1]
      area += a.x * b.y - b.x * a.y
      let dx = b.x - a.x, dy = b.y - a.y
      perim += (dx * dx + dy * dy).squareRoot()
    }
    area = abs(area) * 0.5
    let score = perim > 0 ? (area * .pi * 4) / (perim * perim) : 0.0
    let count = Int((Double(n) * score).rounded(.down))
    return max(count, yStripesMinSegments)
  }

  /// Maps a segment's [segMinY, segMaxY] to the inclusive stripe range [lo, hi].
  private static func segStripeRange(
    _ segMinY: Double, _ segMaxY: Double,
    _ minY: Double, _ height: Double, _ count: Int
  ) -> (Int, Int) {
    guard count > 1 && height > 0 else { return (0, 0) }
    let last = count - 1
    let lo = min(max(Int((segMinY - minY) / height * Double(count)), 0), last)
    let hi = min(max(Int((segMaxY - minY) / height * Double(count)), 0), last)
    return (lo, hi)
  }
}

// MARK: - Indexed ring containment

/// PIP test using a YStripes index when available, linear scan otherwise.
private func ringContainsPoint(
  _ ring: [Point], _ idx: YStripesIndex?, _ point: Point, _ allowOnEdge: Bool
) -> Bool {
  let n = ring.count - 1
  guard n >= 3 else { return false }

  var inside = false

  if let idx = idx {
    idx.forEachCandidate(y: point.y) { i in
      let seg = Segment(a: ring[i], b: ring[i + 1])
      let res = raycast(seg, point)
      if res.on {
        inside = allowOnEdge
        return false  // stop iteration
      }
      if res.inside { inside.toggle() }
      return true
    }
    return inside
  }

  // Linear fallback for small rings.
  let hRect = Rect(
    min: Point(x: -.infinity, y: point.y),
    max: Point(x: .infinity, y: point.y))
  for i in 0..<n {
    let seg = segmentAtForVecPoint(ring, i)
    if seg.rect().intersectsRect(hRect) {
      let res = raycast(seg, point)
      if res.on {
        inside = allowOnEdge
        break
      }
      if res.inside { inside.toggle() }
    }
  }
  return inside
}

// MARK: - Polygon

public struct Polygon {
  public let exterior: [Point]
  public let holes: [[Point]]
  public let rect: Rect
  let extIdx: YStripesIndex?
  let holeIdxs: [YStripesIndex?]

  /// Point-In-Polygon check, the normal way.
  public func containsPointNormal(_ p: Point) -> Bool {
    if !ringContainsPoint(exterior, extIdx, p, false) {
      return false
    }
    for (i, hole) in holes.enumerated() {
      if ringContainsPoint(hole, holeIdxs[i], p, false) {
        return false
      }
    }
    return true
  }

  /// Do point-in-polygon search.
  public func containsPoint(_ p: Point) -> Bool {
    if !rect.containsPoint(p) {
      return false
    }
    return containsPointNormal(p)
  }

  /// Create a new Polygon instance from exterior and holes.
  public static func new(exterior: [Point], holes: [[Point]]) -> Polygon {
    return Polygon.defaultNew(exterior: exterior, holes: holes)
  }

  private static func defaultNew(exterior: [Point], holes: [[Point]]) -> Polygon {
    guard let first = exterior.first else {
      fatalError("Exterior points array cannot be empty")
    }

    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y

    for i in 0..<(exterior.count - 1) {
      let p = exterior[i]
      minX = min(minX, p.x)
      minY = min(minY, p.y)
      maxX = max(maxX, p.x)
      maxY = max(maxY, p.y)
    }

    let rect = Rect(
      min: Point(x: minX, y: minY),
      max: Point(x: maxX, y: maxY)
    )

    // Build YStripes index for rings with enough segments to benefit.
    let extIdx = exterior.count - 1 >= yStripesMinSegments
      ? YStripesIndex(ring: exterior) : nil
    let holeIdxs = holes.map { h in
      h.count - 1 >= yStripesMinSegments ? YStripesIndex(ring: h) : nil
    }

    return Polygon(exterior: exterior, holes: holes, rect: rect, extIdx: extIdx, holeIdxs: holeIdxs)
  }
}
