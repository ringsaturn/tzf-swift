/// Constants and primitives of the TZF embedded binary format (`.tzb`,
/// format 1.1, E profile), mirroring the Go reference implementation in
/// `github.com/ringsaturn/tzf/v2/internal/embedbin` and the tzf-rs port.
import Foundation
import geometry

enum TZB {
  static let headerSize = 64
  static let sectionEntryLen = 16
  static let footerSize = 4
  static let formatMajor: UInt8 = 1
  static let coordScale: UInt32 = 100_000

  /// Header byte assigned as `profile` in format revision 1.1.
  static let profileOffset = 48
  static let profileE: UInt8 = 0
  static let profileM: UInt8 = 1

  static let flagGrid: UInt32 = 1 << 0
  static let flagNoShortcut: UInt32 = 1 << 1

  static let sectionNames: UInt32 = 1
  static let sectionTzDir: UInt32 = 2
  static let sectionPolyDir: UInt32 = 3
  static let sectionRingDir: UInt32 = 4
  static let sectionRingOps: UInt32 = 5
  static let sectionGroupDir: UInt32 = 6
  static let sectionChunkDir: UInt32 = 7
  static let sectionGrid: UInt32 = 8
  static let sectionPoints: UInt32 = 9
  static let sectionFuzzy: UInt32 = 10
  static let sectionFlatPoints: UInt32 = 12
  static let sectionFlatRingDir: UInt32 = 13
  static let sectionYStripes: UInt32 = 14

  /// Sizes the per-type section table (types 1..14).
  static let sectionSlots = 15

  static let tzRecordLen = 24
  static let polyRecordLen = 24
  static let ringRecordLen = 28
  static let groupRecordLen = 44
  static let chunkRecordLen = 24

  static let fuzzyHeaderLen = 16
  /// Marks a FUZZY value word as a multi_dir group reference; the low 15 bits
  /// are then a group index instead of a NAMES index.
  static let fuzzyMulti: UInt16 = 1 << 15

  static let domainMaxX: Int32 = 18_000_000
  static let domainMaxY: Int32 = 9_000_000

  @inline(__always)
  static func pointInDomain(_ p: I32Point) -> Bool {
    p.x >= -domainMaxX && p.x <= domainMaxX && p.y >= -domainMaxY && p.y <= domainMaxY
  }

  @inline(__always)
  static func align4(_ n: Int) -> Int {
    (n + 3) & ~3
  }

  /// Whether a known section type may appear in an E-profile file: the
  /// M-profile section types are structurally invalid here.
  static func sectionAllowed(_ typ: UInt32) -> Bool {
    typ != sectionFlatPoints && typ != sectionFlatRingDir && typ != sectionYStripes
  }

  /// Whether (lng, lat) is finite and inside the ±180/±90 domain.
  @inline(__always)
  static func coordinateInDomain(lng: Double, lat: Double) -> Bool {
    lng.isFinite && lat.isFinite && lng >= -180.0 && lng <= 180.0 && lat >= -90.0 && lat <= 90.0
  }
}

/// Scaled-int32 bounding box, compared in `Double` like the Go reader.
struct TZBBox: Sendable {
  let minX: Int32
  let minY: Int32
  let maxX: Int32
  let maxY: Int32

  @inline(__always)
  var ordered: Bool {
    minX <= maxX && minY <= maxY
  }

  /// Ordered with all bounds in the storage domain (±180°/±90° scaled).
  @inline(__always)
  var inDomain: Bool {
    ordered
      && minX >= -TZB.domainMaxX && maxX <= TZB.domainMaxX
      && minY >= -TZB.domainMaxY && maxY <= TZB.domainMaxY
  }

  @inline(__always)
  func contains(_ x: Double, _ y: Double) -> Bool {
    x >= Double(minX) && x <= Double(maxX) && y >= Double(minY) && y <= Double(maxY)
  }

  /// Whether a leftward ray from (x, y) can interact with segments inside
  /// this box: the raycast counts crossings at `lng >= x` only.
  @inline(__always)
  func rayRelevant(_ x: Double, _ y: Double) -> Bool {
    y >= Double(minY) && y <= Double(maxY) && Double(maxX) >= x
  }
}

// MARK: - CRC32

/// CRC32 (IEEE 802.3), the polynomial Go's `hash/crc32.IEEE` uses.
/// Slicing-by-8: the checksum runs once over the whole file at open, so its
/// throughput dominates `EmbeddedFinder` open time.
enum CRC32 {
  /// Eight 256-entry tables, flattened: table `t` entry `i` is `[t * 256 + i]`.
  static let tables: [UInt32] = {
    var tables = [UInt32](repeating: 0, count: 8 * 256)
    for i in 0..<256 {
      var crc = UInt32(i)
      for _ in 0..<8 {
        crc = (crc & 1) != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
      }
      tables[i] = crc
    }
    for t in 1..<8 {
      for i in 0..<256 {
        let prev = tables[(t - 1) * 256 + i]
        tables[t * 256 + i] = tables[Int(prev & 0xff)] ^ (prev >> 8)
      }
    }
    return tables
  }()

  static func checksum(_ data: UnsafeRawBufferPointer) -> UInt32 {
    return tables.withUnsafeBufferPointer { (t: UnsafeBufferPointer<UInt32>) -> UInt32 in
      var crc: UInt32 = ~0
      var pos = 0
      let n = data.count
      while pos + 8 <= n {
        let lo: UInt32 =
          UInt32(littleEndian: data.loadUnaligned(fromByteOffset: pos, as: UInt32.self)) ^ crc
        let hi: UInt32 =
          UInt32(littleEndian: data.loadUnaligned(fromByteOffset: pos + 4, as: UInt32.self))
        // Split into typed sub-expressions: Swift 6.0's type-checker times
        // out on the single 8-term XOR chain.
        let lo0: Int = Int(lo & 0xff)
        let lo1: Int = Int((lo >> 8) & 0xff)
        let lo2: Int = Int((lo >> 16) & 0xff)
        let lo3: Int = Int(lo >> 24)
        let hi0: Int = Int(hi & 0xff)
        let hi1: Int = Int((hi >> 8) & 0xff)
        let hi2: Int = Int((hi >> 16) & 0xff)
        let hi3: Int = Int(hi >> 24)
        var acc: UInt32 = t[7 * 256 + lo0]
        acc ^= t[6 * 256 + lo1]
        acc ^= t[5 * 256 + lo2]
        acc ^= t[4 * 256 + lo3]
        acc ^= t[3 * 256 + hi0]
        acc ^= t[2 * 256 + hi1]
        acc ^= t[1 * 256 + hi2]
        acc ^= t[hi3]
        crc = acc
        pos += 8
      }
      while pos < n {
        let idx: Int = Int((crc ^ UInt32(data[pos])) & 0xff)
        crc = t[idx] ^ (crc >> 8)
        pos += 1
      }
      return ~crc
    }
  }
}

// MARK: - Varint cursor

/// Zigzag-LEB128 varint cursor over one chunk's byte range. Decoders MUST
/// consume exactly the range: both a varint crossing the boundary and
/// trailing undecoded bytes are malformed-file errors (spec §6.7).
struct StreamCursor {
  let data: UnsafeRawPointer
  var pos: Int
  let end: Int

  @inline(__always)
  init(data: UnsafeRawPointer, pos: Int, end: Int) {
    self.data = data
    self.pos = pos
    self.end = end
  }

  @inline(__always)
  mutating func varint() throws -> Int32 {
    var u: UInt32 = 0
    for i in 0..<5 {
      if pos >= end {
        throw TZFError.malformed("truncated varint")
      }
      let b = data.load(fromByteOffset: pos, as: UInt8.self)
      pos += 1
      if i == 4 && b & 0xf0 != 0 {
        throw TZFError.malformed("varint exceeds 32 bits")
      }
      u |= UInt32(b & 0x7f) << (7 * UInt32(i))
      if b & 0x80 == 0 {
        if i > 0 && b == 0 {
          throw TZFError.malformed("nonminimal varint")
        }
        return Int32(bitPattern: (u >> 1) ^ (0 &- (u & 1)))
      }
    }
    throw TZFError.malformed("unterminated varint")
  }
}

/// Adds a decoded delta to the previous coordinate, rejecting i32 overflow.
@inline(__always)
func addDelta(_ prev: Int32, _ delta: Int32) throws -> Int32 {
  let (v, overflow) = prev.addingReportingOverflow(delta)
  if overflow {
    throw TZFError.malformed("coordinate overflow")
  }
  return v
}
