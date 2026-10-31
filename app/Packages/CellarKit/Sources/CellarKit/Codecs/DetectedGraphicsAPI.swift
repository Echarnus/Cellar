import CellarDomain
import Foundation

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
