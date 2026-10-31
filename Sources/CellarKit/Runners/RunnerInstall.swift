import CellarDomain
import Foundation

/// A runner installed on disk, with its resolved wine binary.
public struct RunnerInstall {
    public let spec: RunnerSpec
    public let root: URL
    public let wineBinary: URL
    public var binDirectory: URL { wineBinary.deletingLastPathComponent() }
    /// `<runner>/wine` for engine-style runners; the `.../Resources/wine` dir for GPTK.
    public var wineRoot: URL { binDirectory.deletingLastPathComponent() }
    /// The wrapper Frameworks directory (renderers + dylibs), when the runner has one.
    public var frameworks: URL? {
        let dir = root.appendingPathComponent("Frameworks", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
    /// `Frameworks/renderer/<name>/wine` — a WINEDLLPATH_PREPEND target — if present.
    public func renderer(_ name: String) -> URL? {
        guard let fw = frameworks else { return nil }
        let dir = fw.appendingPathComponent("renderer/\(name)/wine", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
    /// `<wine>/lib/d3dmetal` — the D3DMetal runtime a WineForge-style Wine reads via D3DMETAL_RUNTIME_DIR.
    public var d3dmetalRuntime: URL? {
        let dir = wineRoot.appendingPathComponent("lib/d3dmetal", isDirectory: true)
        let marker = dir.appendingPathComponent("external/libd3dshared.dylib")
        return FileManager.default.fileExists(atPath: marker.path) ? dir : nil
    }
    /// `<wine>/lib/dxmt` when the Wine build ships DXMT in the WineForge layout.
    public var dxmtRuntime: URL? {
        let dir = wineRoot.appendingPathComponent("lib/dxmt", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
    /// Whether this Wine selects its graphics backend via WineForge's GRAPHICS_BACKEND / *_RUNTIME_DIR
    /// variables (as opposed to Sikarugir's WINEDLLPATH_PREPEND).
    public var isWineForgeStyle: Bool { d3dmetalRuntime != nil || dxmtRuntime != nil }
    /// Whether D3DMetal is available through either mechanism.
    public var hasD3DMetal: Bool { d3dmetalRuntime != nil || renderer("d3dmetal") != nil }

    /// Whether the D3DMetal runtime carries Apple's NVIDIA shims (`nvngx.dll` + `nvapi64.dll`) —
    /// the DLLs a game's DLSS path calls into, which D3DMetal answers with MetalFX. Without them the
    /// NVIDIA identity is a promise the runtime cannot keep, so `WineRunner` presents AMD instead.
    public var hasMetalFXShim: Bool {
        guard let d3dmetal = d3dmetalRuntime else { return false }
        let pe = d3dmetal.appendingPathComponent("wine/x86_64-windows", isDirectory: true)
        return ["nvngx.dll", "nvapi64.dll"].allSatisfy {
            FileManager.default.fileExists(atPath: pe.appendingPathComponent($0).path)
        }
    }

    /// The fast synchronisation mechanisms this Wine build actually implements, read from its
    /// `ntdll.so` rather than assumed from the catalogue. The three macOS builds Cellar knows differ:
    /// Sikarugir (Wine 10) carries msync + esync; WineForge (Wine 11) carries neither and ships its
    /// own **WFUSync** instead — so a `WINEMSYNC=1` there is silently ignored and the game runs on
    /// the slow wineserver path. Measured on the shipped binaries, 2026-09-09.
    public var fastSync: FastSync {
        FastSync.probe(ntdll: ntdllUnix)
    }

    /// `ntdll.so` — the Unix half of ntdll, where the sync backends live. `lib` for wow64 builds,
    /// `lib64` for the GPTK wine64 layout.
    var ntdllUnix: URL? {
        for lib in ["lib", "lib64"] {
            let url = wineRoot.appendingPathComponent("\(lib)/wine/x86_64-unix/ntdll.so")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// The architectures actually present in the installed `wine` binary, read with `lipo`.
    /// This is the ground truth behind `spec.architecture` — a spec can claim anything, the
    /// Mach-O header cannot.
    public var measuredArchitectures: [String] {
        let result = Shell.run("/usr/bin/lipo", ["-archs", wineBinary.path])
        guard result.succeeded else { return [] }
        return result.stdout.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether this install needs Rosetta 2 to run, measured rather than declared.
    /// Falls back to the spec when `lipo` is unavailable.
    public var needsRosetta: Bool {
        let archs = measuredArchitectures
        guard !archs.isEmpty else { return spec.architecture.needsRosetta }
        return !archs.contains { $0.hasPrefix("arm64") }
    }
}
