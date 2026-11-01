import CellarDomain
import Foundation

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
                payloadPath: "WineForge.app/Contents/Resources/Engine/WineForgeCore",
                sha256: "c3610289997966251975cf5b3dd091a881cfe31f09a226215b89df630d946398"),
            RunnerArtifact(
                kind: .d3dmetalFromTemplate,
                url: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.15.tar.xz",
                payloadPath: "Template-1.0.15.app/Contents/Frameworks/renderer/d3dmetal",
                sha256: "34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3"),
        ],
        wineBinaryName: "wine",
        hasD3DMetal: true,
        license: "Wine: LGPL-2.1+ · D3DMetal: Apple proprietary (non-commercial)",
        deprecated: nil
    )

    /// WineForge 0.6.0.8 (Wine 11.21 + CrossOver patches) with Apple D3DMetal 4.0b3, from the
    /// Sikarugir template 1.0.24 (which moved the renderer to `SharedSupport/`). Picked per game by a
    /// profile's `[runner] id`, not the default, because D3DMetal 4 is still a beta: Planet Coaster 2
    /// uses it because D3DMetal 3.0's startup race killed most of its starts (about 1 in 16 got up)
    /// and 4.0b3 started it on the first attempt 3 times out of 3 (cellar verify, 2026-11-01).
    /// Its loader is Developer-ID signed, so the game's app has to be signed again after the copy
    /// (`GameApp`, #247), or macOS kills every start.
    public static let wineforgeD3DMetal4 = RunnerSpec(
        id: "wineforge-d3dmetal4",
        displayName: "WineForge 0.6.0.8 (Wine 11.21 + CrossOver patches) + Apple D3DMetal 4.0b3",
        artifacts: [
            RunnerArtifact(
                kind: .wineDMG,
                url: "https://github.com/Alien4042x/WineForge/releases/download/0.6.0.8/WineForge.dmg",
                payloadPath: "WineForge.app/Contents/Resources/Engine/WineForgeCore",
                sha256: "a4566c654a80234d977b28090d24375e85c29e22d581433217268336addf1a43"),
            RunnerArtifact(
                kind: .d3dmetalFromTemplate,
                url: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.24.tar.xz",
                payloadPath: "Template-1.0.24.app/Contents/SharedSupport/renderer/d3dmetal",
                sha256: "4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c"),
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
                payloadPath: "wswine.bundle",
                sha256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2"),
            RunnerArtifact(
                kind: .wrapperFrameworks,
                url: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.15.tar.xz",
                payloadPath: "Template-1.0.15.app/Contents/Frameworks",
                sha256: "34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3"),
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
                payloadPath: "",
                sha256: "d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e"),
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

    public static let all = [wineforge, wineforgeD3DMetal4, sikarugir, gptk]
    public static let defaultID = wineforge.id
    public static func spec(forID id: String) -> RunnerSpec? { all.first { $0.id == id } }
}
