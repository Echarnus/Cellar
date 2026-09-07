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

/// Describes a downloadable Wine runner family (where to get it, how it's laid out).
public struct RunnerSpec {
    public let id: String            // Cellar id, e.g. "sikarugir"
    public let displayName: String
    public let artifacts: [RunnerArtifact]
    public let wineBinaryName: String // "wine" (wow64 builds) or "wine64" (GPTK)
    public let hasD3DMetal: Bool
    public let license: String
    public let deprecated: String?    // why not to pick it, if applicable
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

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for (index, artifact) in spec.artifacts.enumerated() {
            let ext = artifact.url.hasSuffix(".dmg") ? "dmg" : "tar.xz"
            let archive = Paths.cache.appendingPathComponent("\(spec.id)-\(index).\(ext)")
            if !fm.fileExists(atPath: archive.path) {
                progress("Downloading \(artifact.url)")
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
               url.path.contains("/wine/bin/") {
                return url
            }
        }
        return nil
    }
}
