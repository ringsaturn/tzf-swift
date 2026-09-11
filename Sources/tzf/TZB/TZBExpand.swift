/// Expansion load path (pb-free spec §5.1): decode an E-profile file's
/// geometry into open per-ring point arrays, the exact inputs of the
/// materialized int32 polygon finder.
import Foundation
import geometry

/// One polygon's rings in open form (no closing vertex).
struct ExpandedPolygon: Sendable {
  let exterior: [I32Point]
  let holes: [[I32Point]]
}

/// The decode-once outputs of an E-profile file.
struct Expanded {
  let version: String
  let names: [String]
  /// Indexed by timezone, parallel to `names`.
  let polygons: [[ExpandedPolygon]]
}

extension TZBReader {
  /// Decodes the file's geometry in one sequential pass. Stored junction
  /// duplicates are removed: each op after the first drops its first
  /// streamed point, and the ring's final closing point is dropped, so ring
  /// length equals `RINGDIR.point_count`. The removed vertices are
  /// zero-length PIP no-ops, so queries over the result match the in-place
  /// reader; exported vertex lists simply omit duplicates.
  func expand() throws -> Expanded {
    var groups = [[I32Point]]()
    groups.reserveCapacity(Int(groupCount))
    for i in 0..<groupCount {
      groups.append(try decodeGroup(i))
    }

    var rings = [[I32Point]?]()
    rings.reserveCapacity(Int(ringCount))
    for i in 0..<ringCount {
      rings.append(try expandRing(i) { g in groups[Int(g)] })
    }

    var names = [String]()
    names.reserveCapacity(Int(tzCount))
    var polygons = [[ExpandedPolygon]]()
    polygons.reserveCapacity(Int(tzCount))
    // Rings are consumed exactly once (poly ranges partition RINGDIR), so
    // moving them out avoids a second copy of the whole geometry.
    func takeRing(_ idx: UInt32) throws -> [I32Point] {
      let i = Int(idx)
      guard i < rings.count, let ring = rings[i] else {
        throw TZFError.malformed("ring shared between polygons")
      }
      rings[i] = nil
      return ring
    }
    for i in 0..<tzCount {
      names.append(try name(i))
      let t = try tzAt(i)
      var polys = [ExpandedPolygon]()
      polys.reserveCapacity(Int(t.count))
      for j in 0..<UInt32(t.count) {
        let p = try polyAt(t.first + j)
        let exterior = try takeRing(p.first)
        var holes = [[I32Point]]()
        holes.reserveCapacity(Int(p.count) - 1)
        for h in 1..<UInt32(p.count) {
          holes.append(try takeRing(p.first + h))
        }
        polys.append(ExpandedPolygon(exterior: exterior, holes: holes))
      }
      polygons.append(polys)
    }
    return Expanded(version: version, names: names, polygons: polygons)
  }

  /// Decodes one timezone's polygons, with the same per-ring result
  /// `expand` produces for that timezone. Only the shared-edge groups its
  /// rings reference are decoded — each at most once — so exporting a
  /// single timezone costs a fraction of a full expansion.
  func expandTimezone(_ index: UInt32) throws -> [ExpandedPolygon] {
    if index >= tzCount {
      throw TZFError.indexOutOfRange
    }
    var decoded = [UInt32: [I32Point]]()
    let t = try tzAt(index)
    var polys = [ExpandedPolygon]()
    polys.reserveCapacity(Int(t.count))
    func ringOf(_ idx: UInt32) throws -> [I32Point] {
      let ring = try ringAt(idx)
      for k in 0..<UInt32(ring.count) {
        let word = try opAt(ring.first + k)
        let g = word & 0x7fff_ffff
        if decoded[g] == nil {
          decoded[g] = try decodeGroup(g)
        }
      }
      return try expandRing(idx) { g in decoded[g] ?? [] }
    }
    for j in 0..<UInt32(t.count) {
      let p = try polyAt(t.first + j)
      let exterior = try ringOf(p.first)
      var holes = [[I32Point]]()
      holes.reserveCapacity(Int(p.count) - 1)
      for h in 1..<UInt32(p.count) {
        holes.append(try ringOf(p.first + h))
      }
      polys.append(ExpandedPolygon(exterior: exterior, holes: holes))
    }
    return polys
  }

  /// Decodes one GROUPDIR entry's chunks into its point run and checks the
  /// run against the record's stored endpoints and count.
  private func decodeGroup(_ index: UInt32) throws -> [I32Point] {
    let g = try groupAt(index)
    var points = [I32Point]()
    // Cap the preallocation: point_count is file-controlled, so a forged
    // header must not demand memory before decode proves the data exists.
    points.reserveCapacity(Int(min(g.pointCount, 1 << 16)))
    for j in 0..<UInt32(g.count) {
      let idx = g.first + j
      let chunk = try chunkAt(idx)
      try decodeChunkPoints(idx, chunk, into: &points)
    }
    if points.count != Int(g.pointCount) || points[0] != g.entry
      || points[points.count - 1] != g.exit
    {
      throw TZFError.malformed("group endpoints or count")
    }
    return points
  }

  /// Assembles one ring from its ops, skipping the duplicated junction
  /// vertex at each op boundary and the stored closing vertex.
  private func expandRing(_ index: UInt32, group: (UInt32) throws -> [I32Point]) throws
    -> [I32Point]
  {
    let ring = try ringAt(index)
    var pts = [I32Point]()
    pts.reserveCapacity(Int(min(ring.pointCount + 1, 1 << 16)))
    for k in 0..<UInt32(ring.count) {
      let word = try opAt(ring.first + k)
      let g = try group(word & 0x7fff_ffff)
      if g.isEmpty {
        throw TZFError.malformed("group cache")
      }
      let reversed = word >> 31 != 0
      let skip = k > 0
      if skip {
        let entry = reversed ? g[g.count - 1] : g[0]
        if entry != pts[pts.count - 1] {
          throw TZFError.malformed("junction mismatch")
        }
      }
      if reversed {
        // Ring order is the stored order reversed; the junction duplicate
        // to skip is the *last* stored point.
        pts.append(contentsOf: g.reversed().dropFirst(skip ? 1 : 0))
      } else if skip {
        pts.append(contentsOf: g[1...])
      } else {
        pts.append(contentsOf: g)
      }
    }
    if pts.count != Int(ring.pointCount) + 1 {
      throw TZFError.malformed("ring point count")
    }
    if pts[pts.count - 1] != pts[0] {
      throw TZFError.malformed("closing junction mismatch")
    }
    pts.removeLast()
    return pts
  }
}
