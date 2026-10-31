import CellarDomain
import Foundation

extension GraphicsBackend {
    /// Directory under `Frameworks/renderer/` that implements this backend in a Sikarugir template.
    var rendererDirectory: String {
        switch self {
        case .d3dmetal: return "d3dmetal"
        case .dxmt: return "dxmt"
        case .dxvk: return "dxvk"
        case .vkd3d: return "dxvk"      // no separate vkd3d renderer ships; DXVK dir is the closest
        case .wined3d: return "none"    // builtin Wine D3D: no prepend
        }
    }
}
