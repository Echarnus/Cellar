import Foundation

/// The two facts a draft profile needs from a Windows executable, read from its PE header: which
/// CPU it was built for, and which DLLs it imports — the graphics API shows up there by name.
///
/// Only what is needed, and nothing is executed: the DOS stub's pointer, the COFF machine field,
/// the optional header's import directory, and the section table to turn its addresses into file
/// offsets. A file that isn't a well-formed PE reads as nil rather than as a guess.
public struct PEImage: Sendable, Equatable {
    public enum Machine: String, Sendable {
        case x86 = "x86"
        case x64 = "x86-64"
        case arm64 = "arm64"
        case other
    }

    public let machine: Machine
    /// Imported DLL names, lowercased: `d3d11.dll`, `kernel32.dll`…
    public let imports: [String]

    /// Read at most the first 64 MB — far beyond any header, and a bound on a corrupt offset.
    public static func read(_ url: URL) -> PEImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 << 20) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> PEImage? {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= bytes.count else { return nil }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        guard bytes.count > 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A,           // "MZ"
              let pe = u32(0x3C), pe + 24 <= bytes.count,
              bytes[pe] == 0x50, bytes[pe + 1] == 0x45, bytes[pe + 2] == 0, bytes[pe + 3] == 0,  // "PE\0\0"
              let machineField = u16(pe + 4), let sectionCount = u16(pe + 6),
              let optionalSize = u16(pe + 20) else { return nil }

        let machine: Machine
        switch machineField {
        case 0x014C: machine = .x86
        case 0x8664: machine = .x64
        case 0xAA64: machine = .arm64
        default:     machine = .other
        }

        let optional = pe + 24
        guard let magic = u16(optional) else { return nil }
        // PE32 keeps its data directories 96 bytes in, PE32+ 112; the import table is entry 1.
        let directories: Int
        switch magic {
        case 0x10B: directories = optional + 96
        case 0x20B: directories = optional + 112
        default: return nil
        }
        let sections = optional + optionalSize
        func offset(ofRVA rva: Int) -> Int? {
            for index in 0..<sectionCount {
                let header = sections + index * 40
                guard let virtualSize = u32(header + 8), let virtualAddress = u32(header + 12),
                      let rawSize = u32(header + 16), let rawPointer = u32(header + 20) else { return nil }
                let span = max(virtualSize, rawSize)
                if rva >= virtualAddress, rva < virtualAddress + span {
                    return rva - virtualAddress + rawPointer
                }
            }
            return nil
        }

        var imports: [String] = []
        if let importRVA = u32(directories + 8), importRVA != 0, var descriptor = offset(ofRVA: importRVA) {
            // Import descriptors are 20 bytes each and end with an all-zero one; the name's RVA is at +12.
            while imports.count < 512, let nameRVA = u32(descriptor + 12), nameRVA != 0,
                  let nameOffset = offset(ofRVA: nameRVA) {
                var end = nameOffset
                while end < bytes.count, bytes[end] != 0, end - nameOffset < 256 { end += 1 }
                if let name = String(bytes: bytes[nameOffset..<end], encoding: .ascii), !name.isEmpty {
                    imports.append(name.lowercased())
                }
                descriptor += 20
            }
        }
        return PEImage(machine: machine, imports: imports)
    }
}

/// The graphics API a game draws with, as its imports reveal it, and the backends that suit it.
public enum DetectedGraphicsAPI: String, Sendable, CaseIterable {
    case d3d12, d3d11, d3d10, d3d9, vulkan, opengl, unknown

    /// Strongest evidence first: a game that links both D3D12 and D3D11 (common in Unreal) is a
    /// D3D12 game with an 11 path, and D3DMetal runs both.
    public static func detect(imports: [String]) -> DetectedGraphicsAPI {
        let names = Set(imports.map { $0.lowercased() })
        if names.contains("d3d12.dll") { return .d3d12 }
        if names.contains("d3d11.dll") { return .d3d11 }
        if names.contains("d3d10.dll") || names.contains("d3d10_1.dll") { return .d3d10 }
        if names.contains("d3d9.dll") { return .d3d9 }
        if names.contains("vulkan-1.dll") { return .vulkan }
        if names.contains("opengl32.dll") { return .opengl }
        return .unknown
    }

    /// The profile's spelling: `graphics_api = "DirectX 12"`.
    public var profileValue: String {
        switch self {
        case .d3d12:   return "DirectX 12"
        case .d3d11:   return "DirectX 11"
        case .d3d10:   return "DirectX 10"
        case .d3d9:    return "DirectX 9"
        case .vulkan:  return "Vulkan"
        case .opengl:  return "OpenGL"
        case .unknown: return "unknown"
        }
    }

    /// Backend and fallback, by what each one can actually run (skills/wine-and-runners.md):
    /// D3DMetal does 11 and 12 but no DX9; DXVK does 9–11; VKD3D-Proton is the DX12 alternative.
    public var backends: (backend: GraphicsBackend, fallback: GraphicsBackend) {
        switch self {
        case .d3d12:            return (.d3dmetal, .vkd3d)
        case .d3d11, .d3d10:    return (.d3dmetal, .dxvk)
        case .d3d9:             return (.dxvk, .wined3d)
        case .vulkan:           return (.dxvk, .wined3d)    // native Vulkan goes to MoltenVK either way
        case .opengl:           return (.wined3d, .dxvk)
        case .unknown:          return (.d3dmetal, .dxvk)
        }
    }
}
