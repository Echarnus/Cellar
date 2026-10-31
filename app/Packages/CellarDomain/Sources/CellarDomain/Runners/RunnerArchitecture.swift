import Foundation

/// How a runner's own Mach-O binaries are built — which decides *what* translates the x86-64
/// game code, and therefore whether the runner survives the Rosetta sunset (macOS 28, fall 2027).
///
/// The game itself is an x86-64 Windows binary either way; some x86 translation is always in the
/// loop. The question is only whether that translation is Apple's Rosetta 2 (going away as a
/// general-purpose tool) or an emulator Cellar ships inside the Win32 layer.
public enum RunnerArchitecture: String, Sendable {
    /// x86-64 Wine. Wine, the renderer DLLs and the game all run under **Rosetta 2**.
    case x86_64
    /// arm64 Wine hosting an **ARM64EC** PE world: Wine's own DLLs are native ARM, and x86-64
    /// game code is translated by an emulator inside the layer (FEX) rather than by Rosetta.
    case arm64ec

    /// Whether Apple's Rosetta 2 has to be present for this runner to start at all.
    public var needsRosetta: Bool { self == .x86_64 }

    public var label: String {
        switch self {
        case .x86_64: return "x86_64 (Rosetta 2)"
        case .arm64ec: return "arm64ec (native)"
        }
    }
}
