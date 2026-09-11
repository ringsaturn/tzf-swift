/// Container open/validation, directory records, GRID candidates and the
/// in-place point-in-polygon query walk (spec §8), mirroring the Go
/// `embedbin.Reader` over a byte-backed source.
import Foundation
import geometry

struct TZBSection: Sendable {
  var off: UInt32 = 0
  var len: UInt32 = 0

  @inline(__always)
  var end: Int { Int(off) + Int(len) }
}

struct TZBGridInfo: Sendable {
  let lngMin: Int16
  let latMin: Int16
  let lngCells: UInt16
  let latCells: UInt16
  let candCount: UInt32
  let cellCount: UInt32
  /// Absolute byte offset of the cell-word array.
  let cellsOff: Int
  /// Absolute byte offset of the candidate array.
  let candidatesOff: Int
}

struct TZBTzRecord {
  let first: UInt32
  let count: UInt16
  let bbox: TZBBox
}

struct TZBPolyRecord {
  let first: UInt32
  let count: UInt16
  let bbox: TZBBox
}

struct TZBRingRecord {
  let first: UInt32
  let pointCount: UInt32
  let count: UInt16
  let bbox: TZBBox
}

struct TZBGroupRecord {
  let first: UInt32
  let pointCount: UInt32
  let count: UInt16
  let entry: I32Point
  let exit: I32Point
  let bbox: TZBBox
}

struct TZBChunkRecord {
  let off: UInt32
  let count: UInt16
  let bbox: TZBBox
}

/// An owned, immutable, 8-byte-aligned copy of a file's bytes. Owning the
/// allocation in its own object means it is released exactly once no matter
/// where `TZBReader.init` throws.
final class TZBBuffer: @unchecked Sendable {
  let base: UnsafeRawPointer
  let count: Int

  init(data: Data) {
    let count = data.count
    let buf = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 8)
    data.withUnsafeBytes { src in
      if let start = src.baseAddress, count > 0 {
        buf.copyMemory(from: start, byteCount: count)
      }
    }
    self.base = UnsafeRawPointer(buf)
    self.count = count
  }

  deinit {
    base.deallocate()
  }
}

/// A validated `.tzb` (E profile) file over an owned, immutable byte buffer.
///
/// The buffer is copied once at open and never mutated afterwards, so the
/// reader is safe to share across threads.
final class TZBReader: @unchecked Sendable {
  let buffer: TZBBuffer
  let base: UnsafeRawPointer
  let size: Int
  let flags: UInt32
  let tzCount: UInt32
  let version: String
  let sections: [TZBSection]
  let polyCount: UInt32
  let ringCount: UInt32
  let opCount: UInt32
  let groupCount: UInt32
  let chunkCount: UInt32
  var grid: TZBGridInfo?
  var fuzzy: TZBFuzzyInfo?

  // MARK: - Raw loads (little-endian; callers guarantee in-bounds offsets)

  @inline(__always)
  func u8(_ off: Int) -> UInt8 {
    base.load(fromByteOffset: off, as: UInt8.self)
  }

  @inline(__always)
  func u16(_ off: Int) -> UInt16 {
    UInt16(littleEndian: base.loadUnaligned(fromByteOffset: off, as: UInt16.self))
  }

  @inline(__always)
  func i16(_ off: Int) -> Int16 {
    Int16(bitPattern: u16(off))
  }

  @inline(__always)
  func u32(_ off: Int) -> UInt32 {
    UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off, as: UInt32.self))
  }

  @inline(__always)
  func i32(_ off: Int) -> Int32 {
    Int32(bitPattern: u32(off))
  }

  @inline(__always)
  func u64(_ off: Int) -> UInt64 {
    UInt64(littleEndian: base.loadUnaligned(fromByteOffset: off, as: UInt64.self))
  }

  @inline(__always)
  func bbox(_ off: Int) -> TZBBox {
    TZBBox(minX: i32(off), minY: i32(off + 4), maxX: i32(off + 8), maxY: i32(off + 12))
  }

  /// Checks that `[off, off + len)` lies inside the file.
  @inline(__always)
  func checkRange(_ off: Int, _ len: Int) throws {
    if off < 0 || len < 0 || off > size - len {
      throw TZFError.malformed("read bounds")
    }
  }

  /// The byte offset of directory record `index` in section `typ`.
  @inline(__always)
  func record(_ typ: UInt32, _ index: UInt32, _ count: UInt32, _ width: Int) throws -> Int {
    if index >= count {
      throw TZFError.malformed("directory index")
    }
    let off = Int(sections[Int(typ)].off) + Int(index) * width
    try checkRange(off, width)
    return off
  }

  // MARK: - Open

  /// Validates and opens a byte-backed file (spec §8.1 "open" checks; the
  /// per-record checks below run again on every access, so a structurally
  /// broken record can never be consumed).
  init(data: Data) throws {
    let size = data.count
    if size < TZB.headerSize + TZB.footerSize || size > Int(UInt32.max) {
      throw TZFError.malformed("invalid file size")
    }
    let buffer = TZBBuffer(data: data)
    let base = buffer.base
    self.buffer = buffer
    self.base = base
    self.size = size

    @inline(__always) func u8(_ o: Int) -> UInt8 { base.load(fromByteOffset: o, as: UInt8.self) }
    @inline(__always) func u16(_ o: Int) -> UInt16 {
      UInt16(littleEndian: base.loadUnaligned(fromByteOffset: o, as: UInt16.self))
    }
    @inline(__always) func u32(_ o: Int) -> UInt32 {
      UInt32(littleEndian: base.loadUnaligned(fromByteOffset: o, as: UInt32.self))
    }

    if u8(0) != UInt8(ascii: "T") || u8(1) != UInt8(ascii: "Z") || u8(2) != UInt8(ascii: "F")
      || u8(3) != UInt8(ascii: "B") || u8(4) != TZB.formatMajor
    {
      throw TZFError.malformed("magic or format major")
    }
    // The memory-image (.tzm) profile is a Go-side optimization built on
    // zero-copy ring aliasing; tzf-swift consumes the .tzb profile only.
    switch u8(TZB.profileOffset) {
    case TZB.profileE: break
    case TZB.profileM: throw TZFError.unsupportedProfile
    default: throw TZFError.malformed("unsupported profile")
    }
    if u16(6) != UInt16(TZB.headerSize) || u32(12) != TZB.coordScale || Int(u32(16)) != size {
      throw TZFError.malformed("header fields")
    }
    let flags = u32(8)
    let tzCount = u32(40)
    let chunkTarget = u32(44)
    if tzCount == 0 || tzCount > UInt32(UInt16.max) {
      throw TZFError.malformed("header counts")
    }
    if chunkTarget == 0 || chunkTarget > UInt32(UInt16.max) {
      throw TZFError.malformed("header chunk target")
    }
    var versionBytes = [UInt8]()
    var versionEnded = false
    for i in 24..<40 {
      let b = u8(i)
      if versionEnded {
        if b != 0 { throw TZFError.malformed("data version padding") }
      } else if b == 0 {
        versionEnded = true
      } else {
        versionBytes.append(b)
      }
    }
    guard let version = String(bytes: versionBytes, encoding: .utf8) else {
      throw TZFError.malformed("data version UTF-8")
    }

    let sectionCount = Int(u32(20))
    let tableEnd = TZB.headerSize + sectionCount * TZB.sectionEntryLen
    if tableEnd > size - TZB.footerSize {
      throw TZFError.malformed("section table bounds")
    }
    let footer = u32(size - TZB.footerSize)
    let payload = UnsafeRawBufferPointer(start: base, count: size - TZB.footerSize)
    if CRC32.checksum(payload) != footer {
      throw TZFError.malformed("CRC32")
    }

    func entryAt(_ i: Int) -> (UInt32, TZBSection) {
      let b = TZB.headerSize + i * TZB.sectionEntryLen
      return (u32(b), TZBSection(off: u32(b + 4), len: u32(b + 8)))
    }

    var sections = [TZBSection](repeating: TZBSection(), count: TZB.sectionSlots)
    var seen = [Bool](repeating: false, count: TZB.sectionSlots)
    for i in 0..<sectionCount {
      let (typ, entry) = entryAt(i)
      if entry.off % 4 != 0 {
        throw TZFError.malformed("unaligned section")
      }
      if Int(entry.off) < tableEnd || entry.end > size - TZB.footerSize {
        throw TZFError.malformed("section bounds")
      }
      if typ >= TZB.sectionNames && typ < UInt32(TZB.sectionSlots) {
        let slot = Int(typ)
        if seen[slot] {
          throw TZFError.malformed("duplicate known section")
        }
        if !TZB.sectionAllowed(typ) {
          throw TZFError.malformed("section not valid in profile")
        }
        seen[slot] = true
        sections[slot] = entry
      }
      for j in 0..<i {
        let (_, other) = entryAt(j)
        if Int(entry.off) < other.end && Int(other.off) < entry.end {
          throw TZFError.malformed("overlapping sections")
        }
      }
    }

    // Mandatory sections of the E profile (pb-free spec §6.1).
    for typ in [
      TZB.sectionNames, TZB.sectionTzDir, TZB.sectionPolyDir, TZB.sectionRingDir,
      TZB.sectionRingOps, TZB.sectionGroupDir, TZB.sectionChunkDir, TZB.sectionPoints,
    ] where !seen[Int(typ)] {
      throw TZFError.malformed("missing mandatory section")
    }
    let hasGrid = seen[Int(TZB.sectionGrid)]
    if hasGrid != (flags & TZB.flagGrid != 0) {
      throw TZFError.malformed("GRID flag mismatch")
    }
    if Int(sections[Int(TZB.sectionTzDir)].len) != Int(tzCount) * TZB.tzRecordLen
      || Int(sections[Int(TZB.sectionPolyDir)].len) % TZB.polyRecordLen != 0
      || Int(sections[Int(TZB.sectionRingDir)].len) % TZB.ringRecordLen != 0
      || sections[Int(TZB.sectionRingOps)].len % 4 != 0
      || Int(sections[Int(TZB.sectionGroupDir)].len) % TZB.groupRecordLen != 0
      || Int(sections[Int(TZB.sectionChunkDir)].len) % TZB.chunkRecordLen != 0
    {
      throw TZFError.malformed("directory section length")
    }

    self.flags = flags
    self.tzCount = tzCount
    self.version = version
    self.sections = sections
    self.polyCount = UInt32(Int(sections[Int(TZB.sectionPolyDir)].len) / TZB.polyRecordLen)
    self.ringCount = UInt32(Int(sections[Int(TZB.sectionRingDir)].len) / TZB.ringRecordLen)
    self.opCount = sections[Int(TZB.sectionRingOps)].len / 4
    self.groupCount = UInt32(Int(sections[Int(TZB.sectionGroupDir)].len) / TZB.groupRecordLen)
    self.chunkCount = UInt32(Int(sections[Int(TZB.sectionChunkDir)].len) / TZB.chunkRecordLen)
    self.grid = nil
    self.fuzzy = nil

    if polyCount == 0 || ringCount == 0 || opCount == 0 || groupCount == 0 || chunkCount == 0 {
      throw TZFError.malformed("empty directory")
    }
    try validateNames()
    if hasGrid {
      try validateGrid()
    }
    if seen[Int(TZB.sectionFuzzy)] {
      try validateFuzzy()
    }
    try validateChunkOffsets()
  }

  var dataVersion: String { version }

  var timezoneCount: UInt32 { tzCount }

  var hasFuzzy: Bool { fuzzy != nil }

  var hasGrid: Bool { grid != nil }

  /// A sufficient candidate-buffer capacity for `lookupAll`.
  var lookupBufferSize: Int {
    grid != nil ? 15 : Int(tzCount)
  }

  @inline(__always)
  func section(_ typ: UInt32) -> TZBSection {
    sections[Int(typ)]
  }

  // MARK: - Open-time validation

  private func validateNames() throws {
    let s = sections[Int(TZB.sectionNames)]
    let prefix = 4 + 4 * (Int(tzCount) + 1)
    if Int(s.len) < prefix {
      throw TZFError.malformed("NAMES length")
    }
    let blobLen = u32(Int(s.off))
    if prefix + Int(blobLen) != Int(s.len) {
      throw TZFError.malformed("NAMES blob length")
    }
    var prev: UInt32 = 0
    for i in 0...Int(tzCount) {
      let off = u32(Int(s.off) + 4 + i * 4)
      if off < prev || off > blobLen || (i == Int(tzCount) && off != blobLen) {
        throw TZFError.malformed("NAMES offsets")
      }
      if i > 0 && off == prev {
        throw TZFError.malformed("empty timezone name")
      }
      prev = off
    }
    for i in 0..<tzCount {
      let (start, end) = try nameBounds(i)
      let bytes = UnsafeRawBufferPointer(start: base + start, count: end - start)
      guard let text = String(bytes: bytes, encoding: .utf8) else {
        throw TZFError.malformed("invalid name UTF-8")
      }
      if text.utf8.contains(0) {
        throw TZFError.malformed("NUL in name")
      }
    }
  }

  private func validateGrid() throws {
    let s = sections[Int(TZB.sectionGrid)]
    if s.len < 12 {
      throw TZFError.malformed("GRID length")
    }
    let off = Int(s.off)
    let lngMin = i16(off)
    let latMin = i16(off + 2)
    let lngCells = u16(off + 4)
    let latCells = u16(off + 6)
    let candCount = u32(off + 8)
    if lngCells == 0 || latCells == 0
      || lngMin < -181 || lngMin > 180
      || latMin < -91 || latMin > 90
      || Int(lngMin) + Int(lngCells) - 1 > 181
      || Int(latMin) + Int(latCells) - 1 > 91
      || candCount >= 1 << 28
    {
      throw TZFError.malformed("GRID dimensions")
    }
    let cells = Int(lngCells) * Int(latCells)
    let expect = 12 + cells * 4 + Int(candCount) * 2
    if expect != Int(s.len) {
      throw TZFError.malformed("GRID section size")
    }
    let g = TZBGridInfo(
      lngMin: lngMin, latMin: latMin, lngCells: lngCells, latCells: latCells,
      candCount: candCount, cellCount: UInt32(cells),
      cellsOff: off + 12, candidatesOff: off + 12 + cells * 4)
    for i in 0..<cells {
      let word = u32(g.cellsOff + i * 4)
      let count = word >> 28
      let start = word & 0x0fff_ffff
      if Int(start) + Int(count) > Int(g.candCount) {
        throw TZFError.malformed("GRID candidate range")
      }
      for j in 0..<Int(count) {
        let idx = u16(g.candidatesOff + (Int(start) + j) * 2)
        if UInt32(idx) >= tzCount {
          throw TZFError.malformed("GRID candidate index")
        }
      }
    }
    grid = g
  }

  private func validateChunkOffsets() throws {
    var prev: UInt32 = 0
    let pointsLen = sections[Int(TZB.sectionPoints)].len
    for i in 0..<chunkCount {
      let c = try chunkAt(i)
      if c.count == 0 || c.off >= pointsLen || (i > 0 && c.off <= prev) {
        throw TZFError.malformed("chunk offset or count")
      }
      prev = c.off
    }
  }

  // MARK: - Directory records

  @inline(__always)
  func tzAt(_ index: UInt32) throws -> TZBTzRecord {
    let off = try record(TZB.sectionTzDir, index, tzCount, TZB.tzRecordLen)
    let v = TZBTzRecord(first: u32(off), count: u16(off + 4), bbox: bbox(off + 8))
    if v.count == 0 || Int(v.first) + Int(v.count) > Int(polyCount) || !v.bbox.inDomain {
      throw TZFError.malformed("TZDIR record")
    }
    return v
  }

  @inline(__always)
  func polyAt(_ index: UInt32) throws -> TZBPolyRecord {
    let off = try record(TZB.sectionPolyDir, index, polyCount, TZB.polyRecordLen)
    let v = TZBPolyRecord(first: u32(off), count: u16(off + 4), bbox: bbox(off + 8))
    if v.count == 0 || Int(v.first) + Int(v.count) > Int(ringCount) || !v.bbox.inDomain {
      throw TZFError.malformed("POLYDIR record")
    }
    return v
  }

  @inline(__always)
  func ringAt(_ index: UInt32) throws -> TZBRingRecord {
    let off = try record(TZB.sectionRingDir, index, ringCount, TZB.ringRecordLen)
    let v = TZBRingRecord(
      first: u32(off), pointCount: u32(off + 4), count: u16(off + 8), bbox: bbox(off + 12))
    if v.count == 0 || v.pointCount < 3 || Int(v.first) + Int(v.count) > Int(opCount)
      || !v.bbox.inDomain
    {
      throw TZFError.malformed("RINGDIR record")
    }
    return v
  }

  @inline(__always)
  func opAt(_ index: UInt32) throws -> UInt32 {
    let off = try record(TZB.sectionRingOps, index, opCount, 4)
    let word = u32(off)
    if word & 0x7fff_ffff >= groupCount {
      throw TZFError.malformed("RINGOPS group index")
    }
    return word
  }

  @inline(__always)
  func groupAt(_ index: UInt32) throws -> TZBGroupRecord {
    let off = try record(TZB.sectionGroupDir, index, groupCount, TZB.groupRecordLen)
    let v = TZBGroupRecord(
      first: u32(off), pointCount: u32(off + 4), count: u16(off + 8),
      entry: I32Point(x: i32(off + 12), y: i32(off + 16)),
      exit: I32Point(x: i32(off + 20), y: i32(off + 24)),
      bbox: bbox(off + 28))
    if v.count == 0 || v.pointCount < 2 || Int(v.first) + Int(v.count) > Int(chunkCount)
      || !v.bbox.inDomain || !TZB.pointInDomain(v.entry) || !TZB.pointInDomain(v.exit)
    {
      throw TZFError.malformed("GROUPDIR record")
    }
    var total = 0
    for i in 0..<UInt32(v.count) {
      total += Int(try chunkAt(v.first + i).count)
    }
    if total != Int(v.pointCount) {
      throw TZFError.malformed("group point count")
    }
    return v
  }

  @inline(__always)
  func chunkAt(_ index: UInt32) throws -> TZBChunkRecord {
    let off = try record(TZB.sectionChunkDir, index, chunkCount, TZB.chunkRecordLen)
    let v = TZBChunkRecord(off: u32(off), count: u16(off + 4), bbox: bbox(off + 8))
    if v.count == 0 || v.off >= sections[Int(TZB.sectionPoints)].len || !v.bbox.inDomain {
      throw TZFError.malformed("CHUNKDIR record")
    }
    return v
  }

  // MARK: - Names

  /// Absolute byte bounds of timezone `idx`'s name.
  private func nameBounds(_ idx: UInt32) throws -> (Int, Int) {
    if idx >= tzCount {
      throw TZFError.indexOutOfRange
    }
    let s = sections[Int(TZB.sectionNames)]
    let off = Int(s.off) + 4 + Int(idx) * 4
    let a = Int(u32(off))
    let b = Int(u32(off + 4))
    let baseOff = Int(s.off) + 4 + (Int(tzCount) + 1) * 4
    try checkRange(baseOff + a, b - a)
    return (baseOff + a, baseOff + b)
  }

  /// Compares two names by raw UTF-8 bytes (the spec's multi-result order).
  func nameLess(_ a: UInt32, _ b: UInt32) -> Bool {
    guard let (sa, ea) = try? nameBounds(a), let (sb, eb) = try? nameBounds(b) else {
      return a < b
    }
    let la = ea - sa
    let lb = eb - sb
    let n = min(la, lb)
    for i in 0..<n {
      let ca = u8(sa + i)
      let cb = u8(sb + i)
      if ca != cb { return ca < cb }
    }
    return la < lb
  }

  func name(_ idx: UInt32) throws -> String {
    let (start, end) = try nameBounds(idx)
    let bytes = UnsafeRawBufferPointer(start: base + start, count: end - start)
    guard let text = String(bytes: bytes, encoding: .utf8) else {
      throw TZFError.malformed("name UTF-8")
    }
    return text
  }

  /// All timezone names in directory order.
  func names() throws -> [String] {
    var out = [String]()
    out.reserveCapacity(Int(tzCount))
    for i in 0..<tzCount {
      out.append(try name(i))
    }
    return out
  }

  // MARK: - GRID candidates

  /// The grid candidate range for a query point: `(count, offset, hasGrid)`.
  /// Rejects non-finite and out-of-domain input (spec §8 step 0).
  @inline(__always)
  private func candidates(lng: Double, lat: Double) -> (count: UInt32, off: UInt32, grid: Bool) {
    if !TZB.coordinateInDomain(lng: lng, lat: lat) {
      return (0, 0, grid != nil)
    }
    guard let g = grid else {
      return (tzCount, 0, false)
    }
    let cx = Int(lng.rounded(.down)) - Int(g.lngMin)
    let cy = Int(lat.rounded(.down)) - Int(g.latMin)
    if cx < 0 || cy < 0 || cx >= Int(g.lngCells) || cy >= Int(g.latCells) {
      return (0, 0, true)
    }
    let cell = cy * Int(g.lngCells) + cx
    let word = u32(g.cellsOff + cell * 4)
    return (word >> 28, word & 0x0fff_ffff, true)
  }

  @inline(__always)
  private func candidateAt(_ off: UInt32) throws -> UInt32 {
    guard let g = grid else {
      throw TZFError.malformed("no grid")
    }
    if off >= g.candCount {
      throw TZFError.malformed("candidate offset")
    }
    let idx = UInt32(u16(g.candidatesOff + Int(off) * 2))
    if idx >= tzCount {
      throw TZFError.malformed("candidate index")
    }
    return idx
  }

  /// Copies the dense GRID arrays out of the file: `(info, cell words,
  /// candidates)`. `nil` when the file has no GRID section.
  func gridArrays() -> (info: TZBGridInfo, words: [UInt32], cands: [UInt16])? {
    guard let g = grid else { return nil }
    var words = [UInt32]()
    words.reserveCapacity(Int(g.cellCount))
    for i in 0..<Int(g.cellCount) {
      words.append(u32(g.cellsOff + i * 4))
    }
    var cands = [UInt16]()
    cands.reserveCapacity(Int(g.candCount))
    for i in 0..<Int(g.candCount) {
      cands.append(u16(g.candidatesOff + i * 2))
    }
    return (g, words, cands)
  }

  // MARK: - In-place query walk (E profile)

  /// Returns the first containing timezone index in source order.
  func lookup(lng: Double, lat: Double) throws -> UInt32? {
    let (count, off, hasGrid) = candidates(lng: lng, lat: lat)
    if count == 0 {
      return nil
    }
    // Single-candidate shortcut (spec §8 step 2).
    if hasGrid && count == 1 && flags & TZB.flagNoShortcut == 0
      && lng > -179.0 && lng < 179.0 && lat > -89.0 && lat < 89.0
    {
      return try candidateAt(off)
    }
    let x = lng * Double(TZB.coordScale)
    let y = lat * Double(TZB.coordScale)
    for i in 0..<count {
      let idx = hasGrid ? try candidateAt(off + i) : i
      if try timezoneContains(idx, x, y) {
        return idx
      }
    }
    return nil
  }

  /// All matching indices, sorted lexicographically by name (raw UTF-8
  /// bytes, spec §8 multi-result rule).
  func lookupAll(lng: Double, lat: Double) throws -> [UInt32] {
    var dst = [UInt32]()
    let (count, off, hasGrid) = candidates(lng: lng, lat: lat)
    let x = lng * Double(TZB.coordScale)
    let y = lat * Double(TZB.coordScale)
    for i in 0..<count {
      let idx = hasGrid ? try candidateAt(off + i) : i
      if try timezoneContains(idx, x, y) {
        dst.append(idx)
      }
    }
    dst.sort(by: nameLess)
    return dst
  }

  @inline(__always)
  private func timezoneContains(_ index: UInt32, _ x: Double, _ y: Double) throws -> Bool {
    let t = try tzAt(index)
    if !t.bbox.contains(x, y) {
      return false
    }
    for i in 0..<UInt32(t.count) {
      let p = try polyAt(t.first + i)
      if !p.bbox.contains(x, y) {
        continue
      }
      // Exterior rings allow on-edge containment and hole rings do not: a
      // border query belongs to every polygon touching it, and a point on a
      // hole's boundary stays inside the polygon.
      if !(try ringContains(p.first, x, y, allowOnEdge: true)) {
        continue
      }
      var excluded = false
      for h in 1..<UInt32(p.count) {
        let hr = try ringAt(p.first + h)
        if !hr.bbox.contains(x, y) {
          continue
        }
        if try ringContains(p.first + h, x, y, allowOnEdge: false) {
          excluded = true
          break
        }
      }
      if !excluded {
        return true
      }
    }
    return false
  }

  /// Whether the ring contains (x, y). A point on any ring segment returns
  /// `allowOnEdge`.
  private func ringContains(_ index: UInt32, _ x: Double, _ y: Double, allowOnEdge: Bool) throws
    -> Bool
  {
    let ring = try ringAt(index)
    if !ring.bbox.contains(x, y) {
      return false
    }
    let p = Point(x: x, y: y)
    var inside = false
    var firstEntry = I32Point(x: 0, y: 0)
    var previousExit = I32Point(x: 0, y: 0)
    var sum = 0
    for i in 0..<UInt32(ring.count) {
      let word = try opAt(ring.first + i)
      let group = try groupAt(word & 0x7fff_ffff)
      sum += Int(group.pointCount)
      var entry = group.entry
      var exit = group.exit
      if word >> 31 != 0 {
        swap(&entry, &exit)
      }
      if i == 0 {
        firstEntry = entry
      } else if previousExit != entry {
        // Junction rule (spec §8): encoder-produced files always connect,
        // but a disconnected junction contributes the real segment
        // expansion would create.
        let res = raycastSeg(previousExit.asPoint, entry.asPoint, p)
        if res.on {
          return allowOnEdge
        }
        if res.inside {
          inside.toggle()
        }
      }
      previousExit = exit
      if group.bbox.rayRelevant(x, y), try scanGroup(group, p, &inside) {
        return allowOnEdge
      }
    }
    if sum < Int(ring.count) || sum - Int(ring.count) != Int(ring.pointCount) {
      throw TZFError.malformed("ring point count")
    }
    if previousExit != firstEntry {
      let res = raycastSeg(previousExit.asPoint, firstEntry.asPoint, p)
      if res.on {
        return allowOnEdge
      }
      if res.inside {
        inside.toggle()
      }
    }
    return inside
  }

  /// Scans one group's chunks; returns true when p lies on a segment.
  private func scanGroup(_ group: TZBGroupRecord, _ p: Point, _ inside: inout Bool) throws -> Bool {
    for i in 0..<UInt32(group.count) {
      let chunkIndex = group.first + i
      let chunk = try chunkAt(chunkIndex)
      if !chunk.bbox.rayRelevant(p.x, p.y) {
        continue
      }
      let (last, on) = try scanChunk(chunkIndex, chunk, p, &inside)
      if on {
        return true
      }
      if i + 1 < UInt32(group.count) {
        // Joint segment to the next chunk's first point.
        let next = try chunkAt(chunkIndex + 1)
        let first = try firstChunkPoint(chunkIndex + 1, next)
        let res = raycastSeg(last.asPoint, first.asPoint, p)
        if res.on {
          return true
        }
        if res.inside {
          inside.toggle()
        }
      }
    }
    return false
  }

  /// Evaluates one chunk's internal segments; returns the chunk's last point
  /// and whether p lay on any segment.
  private func scanChunk(
    _ index: UInt32, _ chunk: TZBChunkRecord, _ p: Point, _ inside: inout Bool
  ) throws -> (I32Point, Bool) {
    let (start, end) = try chunkRange(index, chunk)
    var cursor = StreamCursor(data: base, pos: start, end: end)
    var prev = I32Point(x: try cursor.varint(), y: try cursor.varint())
    if !TZB.pointInDomain(prev) {
      throw TZFError.malformed("chunk coordinate domain")
    }
    var onSegment = false
    for _ in 1..<Int(chunk.count) {
      let dx = try cursor.varint()
      let dy = try cursor.varint()
      let next = I32Point(x: try addDelta(prev.x, dx), y: try addDelta(prev.y, dy))
      if !TZB.pointInDomain(next) {
        throw TZFError.malformed("chunk coordinate domain")
      }
      if !onSegment {
        let res = raycastSeg(prev.asPoint, next.asPoint, p)
        if res.on {
          onSegment = true
        } else if res.inside {
          inside.toggle()
        }
      }
      prev = next
    }
    if cursor.pos != end {
      throw TZFError.malformed("trailing chunk bytes")
    }
    return (prev, onSegment)
  }

  func firstChunkPoint(_ index: UInt32, _ chunk: TZBChunkRecord) throws -> I32Point {
    let (start, end) = try chunkRange(index, chunk)
    var cursor = StreamCursor(data: base, pos: start, end: end)
    let p = I32Point(x: try cursor.varint(), y: try cursor.varint())
    if !TZB.pointInDomain(p) {
      throw TZFError.malformed("chunk coordinate domain")
    }
    return p
  }

  /// The absolute byte range of one chunk's stream: `[point_off_k,
  /// point_off_{k+1})`, the last chunk ending at the POINTS section end.
  @inline(__always)
  func chunkRange(_ index: UInt32, _ chunk: TZBChunkRecord) throws -> (Int, Int) {
    let points = sections[Int(TZB.sectionPoints)]
    let start = Int(points.off) + Int(chunk.off)
    let end: Int
    if index + 1 < chunkCount {
      end = Int(points.off) + Int(try chunkAt(index + 1).off)
    } else {
      end = points.end
    }
    if start >= end || end > size {
      throw TZFError.malformed("chunk byte range")
    }
    return (start, end)
  }

  /// Decodes one chunk's full point run, appending to `out`.
  func decodeChunkPoints(_ index: UInt32, _ chunk: TZBChunkRecord, into out: inout [I32Point])
    throws
  {
    let (start, end) = try chunkRange(index, chunk)
    var cursor = StreamCursor(data: base, pos: start, end: end)
    var prev = I32Point(x: try cursor.varint(), y: try cursor.varint())
    if !TZB.pointInDomain(prev) {
      throw TZFError.malformed("point domain")
    }
    out.append(prev)
    for _ in 1..<Int(chunk.count) {
      let dx = try cursor.varint()
      let dy = try cursor.varint()
      prev = I32Point(x: try addDelta(prev.x, dx), y: try addDelta(prev.y, dy))
      if !TZB.pointInDomain(prev) {
        throw TZFError.malformed("point domain")
      }
      out.append(prev)
    }
    if cursor.pos != end {
      throw TZFError.malformed("chunk termination")
    }
  }
}
