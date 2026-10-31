import Foundation

/// Graphics translation backend selected per bottle/profile.
public enum GraphicsBackend: String, CaseIterable, Sendable {
    case d3dmetal   // Apple D3DMetal: DX11/12 -> Metal (fastest for modern games; user-supplied)
    case dxvk       // DXVK: DX9/10/11 -> Vulkan (-> MoltenVK)
    case vkd3d      // VKD3D-Proton: DX12 -> Vulkan (-> MoltenVK)
    case wined3d    // Wine's built-in DX -> OpenGL
    case dxmt       // Community DX11 -> Metal
}
