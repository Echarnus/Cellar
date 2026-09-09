import Foundation

/// Drives a Wine runner against a specific prefix. The x86_64-only Wine binaries are executed
/// directly (Rosetta 2 picks them up); never through `/usr/bin/arch`, since SIP strips `DYLD_*`
/// from system binaries and the runner's dylibs would not resolve.
///
/// The environment mirrors what the Sikarugir wrapper launcher sets up, so a runner assembled from
/// an engine + wrapper Frameworks behaves exactly like the wrapper — without needing its launcher:
/// `WINEDLLPATH_PREPEND` points Wine at the selected renderer's DLLs (D3DMetal, DXMT, DXVK…) and
/// `DYLD_FALLBACK_LIBRARY_PATH` lets their unix halves find D3DMetal.framework / MoltenVK.
public struct WineRunner {
    public let binary: URL       // wine (wow64 builds) or wine64 (GPTK)
    public let prefix: URL       // WINEPREFIX
    public let install: RunnerInstall?
    public let backend: GraphicsBackend

    public init(binary: URL, prefix: URL) {
        self.binary = binary
        self.prefix = prefix
        self.install = nil
        self.backend = .d3dmetal
    }

    public init(install: RunnerInstall, prefix: URL, backend: GraphicsBackend = .d3dmetal) {
        self.binary = install.wineBinary
        self.prefix = prefix
        self.install = install
        self.backend = backend
    }

    /// Base environment. msync is the preferred fast sync on macOS; esync is the fallback.
    public func environment(extra: [String: String] = [:]) -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Start from the caller's environment (TMPDIR, USER, LANG, __CF_USER_TEXT_ENCODING…) and
        // overlay Cellar's variables. A bare environment makes Planet Coaster 2 exit silently ~4 s
        // after launch; an inherited one runs. Same approach as Proton.
        var env = ProcessInfo.processInfo.environment
        // Never let the caller's shell inject Wine/graphics settings from another runner.
        for key in env.keys where key.hasPrefix("WINE") || key.hasPrefix("DYLD_") || key.hasPrefix("D3DM")
            || key.hasPrefix("MTL_") || key.hasPrefix("DXMT_") || key == "GRAPHICS_BACKEND" || key.hasPrefix("GST_") {
            env.removeValue(forKey: key)
        }
        for (k, v) in [
            "WINEPREFIX": prefix.path,
            "WINEDEBUG": "-all",
            "WINEESYNC": "1",
            "WINEMSYNC": "1",
            "WINEBOOT_HIDE_DIALOG": "1",
            "PATH": "\(binary.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home,
        ] { env[k] = v }

        if let install, install.isWineForgeStyle {
            // WineForge: backend selected by GRAPHICS_BACKEND + *_RUNTIME_DIR, DLLs forced native.
            let wineRoot = install.wineRoot.path
            env["WINEDLLPATH"] = "\(wineRoot)/lib/wine"
            env["GST_PLUGIN_PATH"] = "\(wineRoot)/lib/gstreamer-1.0"
            var dyld = ["\(wineRoot)/lib"]
            if let d3dmetal = install.d3dmetalRuntime {
                env["D3DMETAL_RUNTIME_DIR"] = d3dmetal.path
                dyld.append("\(d3dmetal.path)/external")
            }
            if let dxmt = install.dxmtRuntime { env["DXMT_RUNTIME_DIR"] = dxmt.path }
            dyld += ["/usr/lib", "/usr/libexec", "/usr/lib/system"]
            env["DYLD_FALLBACK_LIBRARY_PATH"] = dyld.joined(separator: ":")

            switch backend {
            case .d3dmetal:
                env["GRAPHICS_BACKEND"] = "d3dmetal"
                // AMD identity → FidelityFX upscaler profile; the D3DMetal README's default.
                env["D3DMETAL_UPSCALER_PROFILE"] = "amd"
                env["D3DM_VENDOR_ID"] = "4098"
                env["D3DM_DEVICE_ID"] = "29631"
                env["D3DM_DEVICE_DESCRIPTION"] = "AMD Radeon RX 6800 XT"
                env["WINEDLLOVERRIDES"] = "atidxx64,amdxc64,amd_fidelityfx_upscaler_dx12,amd_fidelityfx_framegeneration_dx12=n,b;dxgi,d3d10,d3d10core,d3d11,d3d12=n,b"
            case .dxmt:
                env["GRAPHICS_BACKEND"] = "dxmt"
                env["WINEDLLOVERRIDES"] = "dxgi,d3d10,d3d10core,d3d11,d3d12,winemetal=b"
            default:
                break
            }
        } else if let install {
            let wineRoot = install.wineRoot.path
            env["WINELOADER"] = binary.path
            env["WINEDLLPATH"] = [
                "\(wineRoot)/lib/wine/x86_64-windows",
                "\(wineRoot)/lib/wine/i386-windows",
                "\(wineRoot)/lib/wine/x86_64-unix",
            ].joined(separator: ":")

            var dyld = ["\(wineRoot)/lib", "\(wineRoot)/lib64"]
            if let fw = install.frameworks {
                dyld += [fw.path, "\(fw.path)/GStreamer.framework/Libraries"]
                env["GST_PLUGIN_PATH"] = "\(fw.path)/GStreamer.framework/Libraries/gstreamer-1.0"
                if let d3dmetal = install.renderer("d3dmetal") { env["WINEDLLPATH_D3DMETAL"] = d3dmetal.path }
                if let dxmt = install.renderer("dxmt") { env["WINEDLLPATH_DXMT"] = dxmt.path }
                if let dxvk = install.renderer("dxvk") { env["WINEDLLPATH_DXVK"] = dxvk.path }
                if let d9vk = install.renderer("d9vk") { env["WINEDLLPATH_D9VK"] = d9vk.path }
                if let rendererDir = install.renderer(backend.rendererDirectory) {
                    env["WINEDLLPATH_PREPEND"] = rendererDir.path
                }
            }
            dyld += ["/opt/wine/lib", "/usr/lib", "/usr/libexec", "/usr/lib/system"]
            env["DYLD_FALLBACK_LIBRARY_PATH"] = dyld.joined(separator: ":")

            // MoltenVK defaults the wrapper ships with.
            env["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"
            env["MVK_CONFIG_FAST_MATH_ENABLED"] = "0"
        }

        // Steam's overlay DLL is injected into every game and crashes under Wine; keep it out.
        env["WINEDLLOVERRIDES"] = [env["WINEDLLOVERRIDES"], "gameoverlayrenderer64=d;gameoverlayrenderer=d"]
            .compactMap { $0 }.joined(separator: ";")

        for (key, value) in extra {
            if key == "WINEDLLOVERRIDES", let existing = env[key], !existing.isEmpty {
                env[key] = existing + ";" + value   // merge, don't clobber the backend's overrides
            } else {
                env[key] = value
            }
        }
        return env
    }

    /// Run wine with arguments. `inheritIO` lets GUIs/long-running processes draw and stream output.
    @discardableResult
    public func run(_ args: [String], extraEnv: [String: String] = [:], inheritIO: Bool = false) -> Shell.Result {
        let env = environment(extra: extraEnv)
        // No `/usr/bin/arch -x86_64` wrapper: SIP strips DYLD_* from system binaries, which breaks
        // the runner (wineserver needs @rpath libs from Frameworks). The x86_64-only Mach-O runs
        // under Rosetta by itself.
        let archArgs = args

        if !inheritIO {
            return Shell.run(binary.path, archArgs, environment: env)
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = archArgs
        process.environment = env
        do { try process.run() } catch {
            return Shell.Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        process.waitUntilExit()
        return Shell.Result(exitCode: process.terminationStatus, stdout: "", stderr: "")
    }

    /// Start wine detached: returns immediately, the Windows process keeps running.
    public func spawn(_ args: [String], extraEnv: [String: String] = [:], log: URL? = nil) throws {
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        process.environment = environment(extra: extraEnv)
        if let log {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
    }

    public func wineVersion() -> String {
        run(["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create the prefix. Suppresses the Mono/Gecko first-run dialogs so init is headless.
    /// A wow64 Wine build (Sikarugir) produces both `Program Files` trees, which the 32-bit Steam
    /// client + 64-bit games need.
    ///
    /// Returns the home folders that had to be redirected into the bottle because macOS refuses
    /// Cellar access to them — empty on the normal path. `wineboot` points the Windows user's
    /// Documents/Desktop/Downloads at the real ones, so a folder the player declined would leave a
    /// game writing saves into a symlink it cannot follow (see `HomeFolderAccess`).
    @discardableResult
    public func initializePrefix() throws -> [HomeFolder] {
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let result = run(["wineboot", "--init"], extraEnv: ["WINEDLLOVERRIDES": "mscoree=d;mshtml=d"])
        guard result.succeeded else {
            throw CellarError.ioFailure("wineboot --init failed: \(result.stderr)")
        }
        waitForServer()
        return HomeFolderAccess.redirectDeniedUserShellFolders(in: prefix)
    }

    /// Set the Windows version (run after initializePrefix so the registry hive exists).
    public func setWindowsVersion(_ version: String = "win10") throws {
        let result = run(["reg", "add", #"HKCU\Software\Wine"#,
                          "/v", "Version", "/t", "REG_SZ", "/d", version, "/f"])
        guard result.succeeded else {
            throw CellarError.ioFailure("Setting Windows version failed: \(result.stderr)")
        }
    }

    /// Run a Windows executable inside the prefix.
    @discardableResult
    public func runExecutable(_ path: String, args: [String] = [],
                              extraEnv: [String: String] = [:], inheritIO: Bool = true) -> Shell.Result {
        run([path] + args, extraEnv: extraEnv, inheritIO: inheritIO)
    }

    private var wineserver: URL {
        binary.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    /// Block until the prefix's wineserver has exited (i.e. all Windows processes are gone).
    public func waitForServer() {
        guard FileManager.default.fileExists(atPath: wineserver.path) else { return }
        Shell.run(wineserver.path, ["-w"], environment: environment())
    }

    /// Stop wineserver (e.g. before deleting a prefix or swapping runners).
    public func killServer() {
        guard FileManager.default.fileExists(atPath: wineserver.path) else { return }
        Shell.run(wineserver.path, ["-k"], environment: environment())
    }

    /// Whether a wineserver is currently alive for this prefix.
    public var serverRunning: Bool {
        // wineserver keeps its socket in /tmp/.wine-<uid>/server-<dev>-<inode>/ keyed on the
        // prefix directory; a live `lock` file there means the server is up.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: prefix.path),
              let dev = attrs[.systemNumber] as? Int, let inode = attrs[.systemFileNumber] as? Int
        else { return false }
        let dir = "/tmp/.wine-\(getuid())/server-\(String(dev, radix: 16))-\(String(inode, radix: 16))"
        let result = Shell.run("/bin/sh", ["-c", "pgrep -f \"\(wineserver.path)\" >/dev/null && test -S \"\(dir)/socket\""], environment: [:])
        return result.succeeded
    }

    /// Environment that activates Apple's D3DMetal niceties. D3DMetal itself needs NO
    /// WINEDLLOVERRIDES — the renderer DLLs are injected through WINEDLLPATH_PREPEND.
    public static func d3dMetalEnv(showHUD: Bool = false) -> [String: String] {
        var env = [
            // D3DM_SUPPORT_DXR is deliberately NOT set: D3DMetal 3.0 exposes ray queries on its own.
            "ROSETTA_ADVERTISE_AVX": "1",   // expose AVX/AVX2 to translated games (macOS 15+)
        ]
        env["MTL_HUD_ENABLED"] = showHUD ? "1" : "0"
        return env
    }
}

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
