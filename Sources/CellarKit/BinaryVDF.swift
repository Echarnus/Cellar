import Foundation

/// A node in Steam's binary key-values (binKV) format used by shortcuts.vdf.
public indirect enum VDFValue {
    case map([(String, VDFValue)])
    case string(String)
    case uint32(UInt32)
}

/// Reader/writer for Steam's binary-VDF (binKV) format.
/// Type bytes: 0x00 = nested map, 0x01 = NUL-terminated string, 0x02 = little-endian uint32,
/// 0x08 = end-of-map. The file is an implicit root map; it ends with two 0x08 bytes.
public enum BinaryVDF {
    public static func parse(_ data: Data) throws -> VDFValue {
        let bytes = [UInt8](data)
        var index = 0
        return .map(try parseMapBody(bytes, &index))
    }

    public static func serialize(_ value: VDFValue) -> Data {
        var out: [UInt8] = []
        if case .map(let entries) = value {
            for (key, child) in entries { serializeEntry(key, child, into: &out) }
            out.append(0x08) // close the implicit root map
        }
        return Data(out)
    }

    // MARK: - Parsing

    private static func parseMapBody(_ bytes: [UInt8], _ index: inout Int) throws -> [(String, VDFValue)] {
        var entries: [(String, VDFValue)] = []
        while index < bytes.count {
            let type = bytes[index]; index += 1
            if type == 0x08 { return entries } // end of this map
            let key = try readCString(bytes, &index)
            switch type {
            case 0x00: entries.append((key, .map(try parseMapBody(bytes, &index))))
            case 0x01: entries.append((key, .string(try readCString(bytes, &index))))
            case 0x02: entries.append((key, .uint32(try readUInt32(bytes, &index))))
            default: throw CellarError.ioFailure("Unknown binary-VDF type byte 0x\(String(type, radix: 16))")
            }
        }
        return entries
    }

    private static func readCString(_ bytes: [UInt8], _ index: inout Int) throws -> String {
        var out: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 0x00 { return String(decoding: out, as: UTF8.self) }
            out.append(byte)
        }
        throw CellarError.ioFailure("Unterminated string in binary VDF")
    }

    private static func readUInt32(_ bytes: [UInt8], _ index: inout Int) throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw CellarError.ioFailure("Truncated uint32 in binary VDF") }
        let value = UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
        index += 4
        return value
    }

    // MARK: - Serializing

    private static func serializeEntry(_ key: String, _ value: VDFValue, into out: inout [UInt8]) {
        switch value {
        case .map(let entries):
            out.append(0x00); appendCString(key, &out)
            for (childKey, child) in entries { serializeEntry(childKey, child, into: &out) }
            out.append(0x08)
        case .string(let string):
            out.append(0x01); appendCString(key, &out); appendCString(string, &out)
        case .uint32(let number):
            out.append(0x02); appendCString(key, &out)
            out.append(UInt8(number & 0xFF))
            out.append(UInt8((number >> 8) & 0xFF))
            out.append(UInt8((number >> 16) & 0xFF))
            out.append(UInt8((number >> 24) & 0xFF))
        }
    }

    private static func appendCString(_ string: String, _ out: inout [UInt8]) {
        out.append(contentsOf: Array(string.utf8))
        out.append(0x00)
    }
}
