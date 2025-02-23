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

public struct Polygon {
  public let exterior: [Point]
  public let holes: [[Point]]
  public let rect: Rect

  /// Point-In-Polygon check, the normal way.
  public func containsPointNormal(_ p: Point) -> Bool {
    if !ringsContainsPoint(exterior, p, false) {
      return false
    }
    var contains = true
    for hole in holes {
      if ringsContainsPoint(hole, p, false) {
        contains = false
        break
      }
    }
    return contains
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

    return Polygon(exterior: exterior, holes: holes, rect: rect)
  }
}
