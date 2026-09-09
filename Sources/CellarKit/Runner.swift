import Foundation

/// One downloadable artifact of a runner and where its payload lands inside the runner root.
public struct RunnerArtifact {
    public enum Kind {
        /// A Wine engine tarball. `payloadPath` is the directory inside the archive that holds
        /// `bin/wine` (e.g. `wswine.bundle`); it is moved to `<runner>/wine`.
        case wineEngine
        /// A Sikarugir/Wineskin wrapper template. Its `Contents/Frameworks` (renderers, D3DMetal,
        /// MoltenVK, GStreamer, dylibs) is moved to `<runner>/Frameworks`.
        case wrapperFrameworks
        /// A GPTK-style `.app` archive that already contains `Contents/Resources/wine/bin`.
        case gptkApp
        /// A `.dmg` holding a Wine tree at `payloadPath` (relative to the mount point); copied to `<runner>/wine`.
        case wineDMG
        /// A Sikarugir/Wineskin wrapper template whose `Contents/Frameworks/renderer/d3dmetal` is
        /// grafted into `<runner>/wine/lib/d3dmetal` — the layout WineForge reads via D3DMETAL_RUNTIME_DIR.
        case d3dmetalFromTemplate
    }
    public let kind: Kind
    public let url: String
    public let payloadPath: String
}

/// How a runner's own Mach-O binaries are built — which decides *what* translates the x86-64
/// game code, and therefore whether the runner survives the Rosetta sunset (macOS 28, fall 2027).
///
/// The game itself is an x86-64 Windows binary either way; some x86 translation is always in the
/// loop. The question is only whether that translation is Apple's Rosetta 2 (going away as a
/// general-purpose tool) or an emulator Cellar ships inside the Win32 layer.
public enum RunnerArchitecture: String {
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

/// Describes a downloadable Wine runner family (where to get it, how it's laid out).
public struct RunnerSpec {
    public let id: String            // Cellar id, e.g. "sikarugir"
    public let displayName: String
    public let artifacts: [RunnerArtifact]
    public let wineBinaryName: String // "wine" (wow64 builds) or "wine64" (GPTK)
    public let hasD3DMetal: Bool
    public let license: String
    public let deprecated: String?    // why not to pick it, if applicable
    /// Declared architecture of the runner's binaries. Defaults to `.x86_64` so a new entry has to
    /// opt in to claiming it is native; `RunnerInstall.measuredArchitectures` checks the claim.
    public var architecture: RunnerArchitecture = .x86_64
    /// The in-layer x86 emulator an ARM64EC runner uses (e.g. "FEX"), when it has one.
    /// `nil` on x86_64 runners — there the translator is Rosetta 2, outside our layer.
    public var emulator: String? = nil
}

/// The runners Cellar knows how to install.
public enum RunnerCatalog {
    /// **Default.** WineForge: Wine 11.17 carrying CodeWeavers' macOS patches, with Apple D3DMetal 3.0
    /// (taken from the Sikarugir template, under Apple's non-commercial grant) as the DX11/12 backend.
    /// Why this and not the others:
    ///  - Wine ≥ 10.8 switches the GS base to the real TEB inside PE code; games that inline
    ///    `GetCurrentFiber()` as `mov rax, gs:[0x20]` (Frontier's COBRA engine: Planet Coaster 2)
    ///    crash on older Wine because macOS keeps its own pthread block in GS.
    ///  - Stock Wine 11 dropped the `ntdll.__wine_unix_call` export that D3DMetal's DLLs import;
    ///    WineForge keeps a compatibility path, so D3DMetal 3.0 loads on Wine 11.
    public static let wineforge = RunnerSpec(
        id: "wineforge",
        displayName: "WineForge 0.6.0.4 (Wine 11.17 + CrossOver patches) + Apple D3DMetal 3.0",
        artifacts: [
            RunnerArtifact(
                kind: .wineDMG,
                url: "https://github.com/Alien4042x/WineForge/releases/download/0.6.0.4/WineForge.dmg",
                payloadPath: "WineForge.app/Contents/Resources/Engine/WineForgeCore"),
            RunnerArtifact(
                kind: .d3dmetalFromTemplate,
                url: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.15.tar.xz",
                payloadPath: "Template-1.0.15.app/Contents/Frameworks/renderer/d3dmetal"),
        ],
        wineBinaryName: "wine",
        hasD3DMetal: true,
        license: "Wine: LGPL-2.1+ · D3DMetal: Apple proprietary (non-commercial)",
        deprecated: nil
    )

    public static let sikarugir = RunnerSpec(
        id: "sikarugir",
        displayName: "Wine 10 (Sikarugir) + Apple D3DMetal 3.0",
        artifacts: [
            RunnerArtifact(
                kind: .wineEngine,
                url: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz",
                payloadPath: "wswine.bundle"),
            RunnerArtifact(
                kind: .wrapperFrameworks,
                url: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.15.tar.xz",
                payloadPath: "Template-1.0.15.app/Contents/Frameworks"),
        ],
        wineBinaryName: "wine",
        hasD3DMetal: true,
        license: "Wine: LGPL-2.1+ · D3DMetal: Apple proprietary (non-commercial) · MoltenVK: Apache-2.0",
        deprecated: "Wine 10.0: games that inline GetCurrentFiber() (e.g. Planet Coaster 2) crash; prefer 'wineforge'."
    )

    /// Apple's Game Porting Toolkit as redistributed by Gcenx: Wine 7.7 + D3DMetal 3.0.
    /// Kept for experiments; the Windows Steam client no longer runs on this Wine.
    public static let gptk = RunnerSpec(
        id: "gptk",
        displayName: "Game Porting Toolkit (Wine 7.7 + Apple D3DMetal)",
        artifacts: [
            RunnerArtifact(
                kind: .gptkApp,
                url: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz",
                payloadPath: ""),
        ],
        wineBinaryName: "wine64",
        hasD3DMetal: true,
        license: "Wine: LGPL-2.1+ · D3DMetal: Apple proprietary (non-commercial)",
        deprecated: "Wine 7.7 crash-loops the Steam web helper (steamwebhelper); use 'sikarugir'."
    )

    // MARK: - The native ARM64EC runner (migration target, not yet shippable)
    //
    // Every runner above is `.x86_64`: Wine, the D3DMetal DLLs and the game all go through
    // Rosetta 2. macOS 27 is the last release with general-purpose Rosetta; macOS 28 (fall 2027)
    // keeps only a gaming-focused subset, and Apple has not said whether a Wine layer qualifies.
    //
    // The replacement is an arm64 Wine with an ARM64EC PE world plus FEX as the in-layer x86
    // emulator — the same architecture CodeWeavers shipped as a CrossOver Mac ARM64 preview in
    // July 2026. Both halves are free (Wine LGPL-2.1+, FEX MIT), so a community build is a
    // question of packaging, not licensing. Adding it here is a catalog entry, not a rewrite:
    // set `architecture: .arm64ec`, `emulator: "FEX"`, and point the artifacts at the build.
    //
    // Three upstream gates, all outside Cellar's control — see docs/ROADMAP.md Phase 5:
    //   1. A free, prebuilt arm64 macOS Wine with the ARM64EC hook (Gcenx/Sikarugir/WineForge).
    //   2. FEX's macOS port available as that hook (CodeWeavers' fork upstreamed, or equivalent).
    //   3. A renderer with ARM64EC PE DLLs: Apple's D3DMetal 4 (GPTK 4 / Metal 4, macOS 27), or
    //      DXVK + VKD3D-Proton on MoltenVK rebuilt for arm64ec — the fully-free fallback.
    // `cellar doctor` reports which of these the installed runner already satisfies.

    public static let all = [wineforge, sikarugir, gptk]
    public static let defaultID = wineforge.id
    public static func spec(forID id: String) -> RunnerSpec? { all.first { $0.id == id } }
}

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

public enum RunnerManager {
    /// List installed runners (those Cellar recognises and whose wine binary is present).
    public static func installed() -> [RunnerInstall] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Paths.runners, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { dir in
            guard let spec = RunnerCatalog.spec(forID: dir.lastPathComponent),
                  let bin = locateWineBinary(in: dir, name: spec.wineBinaryName) else { return nil }
            return RunnerInstall(spec: spec, root: dir, wineBinary: bin)
        }.sorted { $0.spec.id < $1.spec.id }
    }

    public static func find(id: String) -> RunnerInstall? {
        installed().first { $0.spec.id == id }
    }

    /// Install a runner (idempotent — returns the existing install if already present).
    @discardableResult
    public static func install(_ spec: RunnerSpec, progress: (String) -> Void = { _ in }) throws -> RunnerInstall {
        try Paths.ensureBaseDirectories()
        let fm = FileManager.default
        let dest = Paths.runners.appendingPathComponent(spec.id, isDirectory: true)

        if let bin = locateWineBinary(in: dest, name: spec.wineBinaryName) {
            progress("\(spec.displayName) already installed.")
            return RunnerInstall(spec: spec, root: dest, wineBinary: bin)
        }
        CellarLog.info(.runner, "Installing runner \(spec.displayName) "
            + "(\(spec.artifacts.count) artifact(s) to download).", subject: spec.id)

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for (index, artifact) in spec.artifacts.enumerated() {
            let ext = artifact.url.hasSuffix(".dmg") ? "dmg" : "tar.xz"
            let archive = Paths.cache.appendingPathComponent("\(spec.id)-\(index).\(ext)")
            if !fm.fileExists(atPath: archive.path) {
                progress("Downloading \(artifact.url)")
                CellarLog.debug(.runner, "Downloading \(artifact.url)", subject: spec.id)
                try Downloader.fetch(artifact.url, to: archive)
            } else {
                progress("Using cached \(archive.lastPathComponent)")
            }

            if artifact.kind == .wineDMG {
                progress("Copying Wine out of \(archive.lastPathComponent)…")
                let target = dest.appendingPathComponent("wine", isDirectory: true)
                try? fm.removeItem(at: target)
                try Archive.withMountedDMG(archive) { mount in
                    try fm.copyItem(at: mount.appendingPathComponent(artifact.payloadPath), to: target)
                }
                try? fm.removeItem(at: archive)
                continue
            }

            let staging = Paths.cache.appendingPathComponent("\(spec.id)-\(index)-extract", isDirectory: true)
            try? fm.removeItem(at: staging)
            progress("Extracting \(archive.lastPathComponent)…")
            try Archive.extractTar(archive, to: staging)

            switch artifact.kind {
            case .wineDMG:
                break // handled above
            case .d3dmetalFromTemplate:
                let payload = staging.appendingPathComponent(artifact.payloadPath)
                let target = dest.appendingPathComponent("wine/lib/d3dmetal", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: payload, to: target)
            case .wineEngine:
                let payload = staging.appendingPathComponent(artifact.payloadPath)
                let target = dest.appendingPathComponent("wine", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: payload, to: target)
            case .wrapperFrameworks:
                let payload = staging.appendingPathComponent(artifact.payloadPath)
                let target = dest.appendingPathComponent("Frameworks", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: payload, to: target)
            case .gptkApp:
                // The archive already is the runner layout (`<name>.app/Contents/Resources/wine`).
                for item in try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
                    try fm.moveItem(at: item, to: dest.appendingPathComponent(item.lastPathComponent))
                }
            }
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: archive)
        }

        guard let bin = locateWineBinary(in: dest, name: spec.wineBinaryName) else {
            throw CellarError.ioFailure(
                "Could not find '\(spec.wineBinaryName)' after installing \(spec.displayName).")
        }
        return RunnerInstall(spec: spec, root: dest, wineBinary: bin)
    }

    // MARK: - Internals

    /// Find `.../bin/<name>` inside a runner root. Engine runners keep it at `wine/bin/<name>`;
    /// GPTK keeps it at `<app>/Contents/Resources/wine/bin/<name>`.
    static func locateWineBinary(in root: URL, name: String) -> URL? {
        let direct = root.appendingPathComponent("wine/bin/\(name)")
        if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == name, url.deletingLastPathComponent().lastPathComponent == "bin",
               url.path.contains("/wine/bin/"),
               // Same demand as the direct path above. Without it a half-extracted download, or one
               // whose permissions were stripped, reports as an installed runner and then fails at
               // exec time with something nobody can read — rather than honestly saying it is not
               // installed yet.
               FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
