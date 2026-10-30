import Foundation

/// Which graphics backend a game actually runs on.
///
/// A profile names two: `backend`, the one it was tested on, and `fallback_backend`, the one to try
/// when that does not bring the game up on a given Mac. The player's switch to the fallback is kept
/// in the bottle (`bottle.toml`), never in the profile, so a profile update cannot quietly undo a
/// choice that made the game start.
public enum BackendChoice {
    /// Its own key, not the `backend` line `PrefixManager.create` writes: that one records what the
    /// bottle was made with, and reading it as a choice would pin every game to its day-one backend.
    static let key = "graphics_backend"

    /// The backend the player picked for this bottle; nil means the profile's.
    public static func chosen(in url: URL) -> GraphicsBackend? {
        BottleConfig.fields(url)[key].flatMap { GraphicsBackend(rawValue: $0.lowercased()) }
    }

    /// Remember `backend` for this bottle, or forget the choice with nil.
    public static func set(_ backend: GraphicsBackend?, in url: URL) throws {
        if let backend {
            try BottleConfig.set(key: key, to: backend.rawValue, section: "graphics", in: url)
        } else {
            try BottleConfig.unset(key: key, in: url)
        }
    }

    /// The one backend worth offering after `current` failed to bring the game up: the profile's
    /// fallback, and only while the game is still on its primary. Once it is on the fallback there
    /// is nothing further to offer, so a retry that fails too never turns into a loop.
    public static func retry(current: String, primary: String, fallback: String?) -> GraphicsBackend? {
        guard let fallback, current == primary, fallback != current else { return nil }
        return GraphicsBackend(rawValue: fallback)
    }
}

extension GraphicsBackend {
    /// The name the player reads — the project's own spelling, not the profile's lowercase id.
    public var displayName: String {
        switch self {
        case .d3dmetal: return "D3DMetal"
        case .dxvk:     return "DXVK"
        case .vkd3d:    return "VKD3D-Proton"
        case .wined3d:  return "WineD3D"
        case .dxmt:     return "DXMT"
        }
    }

    /// One sentence on what switching to this backend changes, for the button that offers it.
    public var summary: String {
        switch self {
        case .d3dmetal: return "Apple's D3DMetal translates DirectX straight to Metal."
        case .dxvk:     return "DXVK translates DirectX to Vulkan, which MoltenVK then runs on Metal."
        case .vkd3d:    return "VKD3D-Proton translates DirectX 12 to Vulkan, which MoltenVK then runs on Metal."
        case .wined3d:  return "Wine's own translator draws through OpenGL: the slowest, and the most forgiving."
        case .dxmt:     return "DXMT translates DirectX 11 straight to Metal."
        }
    }

    /// Accepts the profile id or the display name, in any case.
    public init?(named text: String) {
        let wanted = text.lowercased()
        guard let match = GraphicsBackend.allCases.first(where: {
            $0.rawValue == wanted || $0.displayName.lowercased() == wanted
        }) else { return nil }
        self = match
    }
}
