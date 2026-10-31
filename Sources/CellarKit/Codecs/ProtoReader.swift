import Foundation

/// Just enough protobuf to walk a message: varints, length-delimited fields, and skipping the rest.
///
/// Read by `depot.config` (`GameUpdate`) and Steam's saved sign-ins (`DepotAccountStore`).
struct ProtoReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func varint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func tag() -> (field: UInt64, wire: UInt64)? {
        guard let key = varint() else { return nil }
        return (key >> 3, key & 0x7)
    }

    mutating func lengthDelimited() -> [UInt8]? {
        guard let length = varint(), let count = Int(exactly: length),
              count <= bytes.count - index else { return nil }
        defer { index += count }
        return Array(bytes[index..<index + count])
    }

    mutating func skip(wire: UInt64) -> Bool {
        switch wire {
        case 0: return varint() != nil
        case 1: guard bytes.count - index >= 8 else { return false }; index += 8; return true
        case 2: return lengthDelimited() != nil
        case 5: guard bytes.count - index >= 4 else { return false }; index += 4; return true
        default: return false
        }
    }
}
