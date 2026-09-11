/// FUZZY section (type 10): the preindex tile set stored as one sorted key
/// array (pb-free spec §4). Validated at open; queried in place by the
/// embedded finder and materialized into a hash map by the default finder.
import Foundation

struct TZBFuzzyInfo: Sendable {
  let idxZoom: UInt8
  let aggZoom: UInt8
  let tileCount: UInt32
  let multiGroupCount: UInt32
  let multiValueCount: UInt32
  /// Absolute byte offsets.
  let keysOff: Int
  let valuesOff: Int
  let multiDirOff: Int
  let multiValuesOff: Int
  let maxGroupLen: UInt32
}

extension TZBReader {
  /// Checks the FUZZY section's structure: exact length for the stored
  /// counts, ordered keys, and resolvable values. Semantic parity with the
  /// source preindex is the build pipeline's job (spec §8.1 trust model).
  func validateFuzzy() throws {
    let s = section(TZB.sectionFuzzy)
    if s.off % 8 != 0 {
      throw TZFError.malformed("FUZZY section alignment")
    }
    if Int(s.len) < TZB.fuzzyHeaderLen {
      throw TZFError.malformed("FUZZY length")
    }
    let off = Int(s.off)
    let idxZoom = u8(off)
    let aggZoom = u8(off + 1)
    let tileCount = u32(off + 4)
    let multiGroupCount = u32(off + 8)
    let multiValueCount = u32(off + 12)
    if u8(off + 2) != 0 || u8(off + 3) != 0 || aggZoom > idxZoom || idxZoom > 28 || tileCount == 0 {
      throw TZFError.malformed("FUZZY header")
    }
    let size =
      TZB.fuzzyHeaderLen + 8 * Int(tileCount) + 2 * Int(tileCount) + 4 * Int(multiGroupCount)
      + 2 * Int(multiValueCount)
    if TZB.align4(size) != Int(s.len) {
      throw TZFError.malformed("FUZZY section size")
    }
    let keysOff = off + TZB.fuzzyHeaderLen
    let valuesOff = keysOff + 8 * Int(tileCount)
    let multiDirOff = valuesOff + 2 * Int(tileCount)
    let multiValuesOff = multiDirOff + 4 * Int(multiGroupCount)
    for pad in size..<Int(s.len) where u8(off + pad) != 0 {
      throw TZFError.malformed("FUZZY padding")
    }

    var prev: UInt64 = 0
    for i in 0..<Int(tileCount) {
      let key = u64(keysOff + 8 * i)
      if i > 0 && key <= prev {
        throw TZFError.malformed("FUZZY keys not strictly ascending")
      }
      prev = key
      let z = UInt8(truncatingIfNeeded: key >> 56)
      if z < aggZoom || z > idxZoom {
        throw TZFError.malformed("FUZZY key zoom")
      }
      let value = u16(valuesOff + 2 * i)
      if value & TZB.fuzzyMulti == 0 {
        if UInt32(value) >= tzCount {
          throw TZFError.malformed("FUZZY value index")
        }
      } else if UInt32(value & ~TZB.fuzzyMulti) >= multiGroupCount {
        throw TZFError.malformed("FUZZY multi group index")
      }
    }
    var maxGroupLen: UInt32 = 1
    for g in 0..<Int(multiGroupCount) {
      let goff = multiDirOff + 4 * g
      let first = u16(goff)
      let count = u16(goff + 2)
      if count == 0 || UInt32(first) + UInt32(count) > multiValueCount {
        throw TZFError.malformed("FUZZY multi group range")
      }
      maxGroupLen = max(maxGroupLen, UInt32(count))
    }
    for i in 0..<Int(multiValueCount) where UInt32(u16(multiValuesOff + 2 * i)) >= tzCount {
      throw TZFError.malformed("FUZZY multi value index")
    }
    fuzzy = TZBFuzzyInfo(
      idxZoom: idxZoom, aggZoom: aggZoom, tileCount: tileCount,
      multiGroupCount: multiGroupCount, multiValueCount: multiValueCount,
      keysOff: keysOff, valuesOff: valuesOff, multiDirOff: multiDirOff,
      multiValuesOff: multiValuesOff, maxGroupLen: maxGroupLen)
  }

  @inline(__always)
  private func fuzzyKeyAt(_ f: TZBFuzzyInfo, _ i: UInt32) -> UInt64 {
    u64(f.keysOff + 8 * Int(i))
  }

  @inline(__always)
  private func fuzzyGroupAt(_ f: TZBFuzzyInfo, _ g: UInt32) -> (first: UInt16, count: UInt16) {
    let off = f.multiDirOff + 4 * Int(g)
    return (u16(off), u16(off + 2))
  }

  /// Binary-searches the sorted key array. Because zoom occupies the key's
  /// high bits, a per-zoom probe is a single search.
  @inline(__always)
  private func fuzzySearch(_ f: TZBFuzzyInfo, _ target: UInt64) -> UInt32? {
    var lo: UInt32 = 0
    var hi = f.tileCount
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if fuzzyKeyAt(f, mid) < target {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo < f.tileCount && fuzzyKeyAt(f, lo) == target {
      return lo
    }
    return nil
  }

  /// Walks zoom levels coarsest-first and returns the first hit's value
  /// word: the tile-map lookup loop with the hash maps replaced by one
  /// sorted array.
  @inline(__always)
  private func fuzzyProbe(lng: Double, lat: Double) throws -> UInt16? {
    guard let f = fuzzy else {
      throw TZFError.noFuzzySection
    }
    if !TZB.coordinateInDomain(lng: lng, lat: lat) {
      return nil
    }
    let tile = TileID(lng: lng, lat: lat, zoom: UInt32(f.idxZoom))
    for z in f.aggZoom...f.idxZoom {
      let key = tile.shift(f.idxZoom - z).raw
      if let pos = fuzzySearch(f, key) {
        return u16(f.valuesOff + 2 * Int(pos))
      }
    }
    return nil
  }

  /// The FUZZY tile match for (lng, lat), if any. Multi-name tiles resolve
  /// to the group's first entry (first-listed wins).
  func fuzzyLookup(lng: Double, lat: Double) throws -> UInt32? {
    guard let value = try fuzzyProbe(lng: lng, lat: lat) else {
      return nil
    }
    if value & TZB.fuzzyMulti == 0 {
      return UInt32(value)
    }
    guard let f = fuzzy else {
      throw TZFError.noFuzzySection
    }
    let (first, _) = fuzzyGroupAt(f, UInt32(value & ~TZB.fuzzyMulti))
    return UInt32(u16(f.multiValuesOff + 2 * Int(first)))
  }

  /// Materializes the FUZZY section into `(key, indices)` pairs, in stored
  /// (ascending key) order; multi groups keep their stored order.
  func fuzzyEntries() throws -> [(key: UInt64, indices: [UInt16])] {
    guard let f = fuzzy else {
      throw TZFError.noFuzzySection
    }
    var out = [(key: UInt64, indices: [UInt16])]()
    out.reserveCapacity(Int(f.tileCount))
    for i in 0..<f.tileCount {
      let key = fuzzyKeyAt(f, i)
      let value = u16(f.valuesOff + 2 * Int(i))
      if value & TZB.fuzzyMulti == 0 {
        out.append((key, [value]))
        continue
      }
      let (first, count) = fuzzyGroupAt(f, UInt32(value & ~TZB.fuzzyMulti))
      var group = [UInt16]()
      group.reserveCapacity(Int(count))
      for j in 0..<Int(count) {
        group.append(u16(f.multiValuesOff + 2 * (Int(first) + j)))
      }
      out.append((key, group))
    }
    return out
  }

  /// The FUZZY section's `(idxZoom, aggZoom)`.
  var fuzzyZooms: (idxZoom: UInt8, aggZoom: UInt8)? {
    fuzzy.map { ($0.idxZoom, $0.aggZoom) }
  }
}
