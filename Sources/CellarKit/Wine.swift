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
    /// The profile asked for MetalFX (`metalfx_upscaling = true`). Honoured only where the runtime
    /// can deliver it — see `environment()`.
    public let metalFX: Bool
    /// The language Wine — and so the store client and the game — runs in. Nil leaves the locale
    /// to the caller's environment, which is only right for a call that shows nothing (`--version`).
    public let language: GameLanguage?

    public init(binary: URL, prefix: URL) {
        self.binary = binary
        self.prefix = prefix
        self.install = nil
        self.backend = .d3dmetal
        self.metalFX = false
        self.language = nil
    }

    public init(install: RunnerInstall, prefix: URL, backend: GraphicsBackend = .d3dmetal, metalFX: Bool = false,
                language: GameLanguage? = nil) {
        self.binary = install.wineBinary
        self.prefix = prefix
        self.install = install
        self.backend = backend
        self.metalFX = metalFX
        self.language = language
    }

    /// Whether this launch will actually present the NVIDIA identity and so get MetalFX: asked
    /// for by the profile, on a runtime that ships the `nvngx`/`nvapi64` shims, on D3DMetal.
    public var usesMetalFX: Bool {
        metalFX && backend == .d3dmetal && (install?.hasMetalFXShim ?? false)
    }

    /// Base environment. The fast-sync variables are the ones this build's `ntdll.so` recognises
    /// (`FastSync`) — WineForge wants `WINEWFUSYNC`, Sikarugir `WINEMSYNC`/`WINEESYNC`, and a
    /// variable a build does not know is ignored, which is how the default runner ran without any
    /// fast sync until this was measured.
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
            "WINEBOOT_HIDE_DIALOG": "1",
            "PATH": "\(binary.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home,
        ] { env[k] = v }
        for variable in (install?.fastSync ?? .unknown).variables { env[variable] = "1" }
        if let language {
            // The inherited locale is whatever shell started Cellar — see `GameLanguage`.
            env.removeValue(forKey: "LANGUAGE")
            for (k, v) in language.environment { env[k] = v }
        }

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
                if usesMetalFX {
                    // NVIDIA identity: the game takes its DLSS path, D3DMetal's nvngx shim answers
                    // it with MetalFX. Apple's own upscaler on Apple's own GPU — the GPU-side lever
                    // for a GPU-bound scene. Both blocks are WineForge's documented identities.
                    env["D3DMETAL_UPSCALER_PROFILE"] = "nvidia"
                    env["D3DM_VENDOR_ID"] = "4318"
                    env["D3DM_DEVICE_ID"] = "10370"
                    env["D3DM_DEVICE_DESCRIPTION"] = "NVIDIA GeForce RTX 4080"
                    env["D3DM_ENABLE_METALFX"] = "1"
                    env["WINEDLLOVERRIDES"] = "dxgi,d3d10,d3d10core,d3d11,d3d12=n,b;nvapi,nvapi64,nvngx=b"
                } else {
                    // AMD identity → FidelityFX upscaler profile; the D3DMetal README's default.
                    env["D3DMETAL_UPSCALER_PROFILE"] = "amd"
                    env["D3DM_VENDOR_ID"] = "4098"
                    env["D3DM_DEVICE_ID"] = "29631"
                    env["D3DM_DEVICE_DESCRIPTION"] = "AMD Radeon RX 6800 XT"
                    env["WINEDLLOVERRIDES"] = "atidxx64,amdxc64,amd_fidelityfx_upscaler_dx12,amd_fidelityfx_framegeneration_dx12=n,b;dxgi,d3d10,d3d10core,d3d11,d3d12=n,b"
                }
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
        // Wherever the HUD is on, have it log its numbers too (one line a second), so
        // `cellar perf measure` can report what the player just saw instead of asking them to read it.
        if env["MTL_HUD_ENABLED"] == "1", env["MTL_HUD_LOG_ENABLED"] == nil {
            env["MTL_HUD_LOG_ENABLED"] = "1"
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
    ///
    /// `bundledLoader` is a copy of this runner's loader inside the game's `.app` (`GameApp`). When
    /// given, that copy is what runs — so macOS sees the game's bundle — with `argv[0]` still naming
    /// the runner's own binary, which is where Wine's loader looks for the rest of itself.
    public func spawn(_ args: [String], extraEnv: [String: String] = [:], log: URL? = nil,
                      bundledLoader: URL? = nil) throws {
        if let bundledLoader {
            try spawnBundled(bundledLoader, args, environment: environment(extra: extraEnv), log: log)
            return
        }
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

    /// `Process` always passes the executable's own path as `argv[0]`, so the bundled start goes
    /// through `posix_spawn` directly — set up the way `Process` does it (signals reset, no stray
    /// descriptors inherited) — and is reaped in the background so it never lingers as a zombie.
    private func spawnBundled(_ executable: URL, _ args: [String], environment: [String: String],
                              log: URL?) throws {
        let output = log?.path ?? "/dev/null"
        if let log {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output, O_WRONLY | O_APPEND, 0)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes,
                                 Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var every = sigset_t()
        sigfillset(&every)
        posix_spawnattr_setsigdefault(&attributes, &every)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)

        let argv: [UnsafeMutablePointer<CChar>?] = ([binary.path] + args).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        guard status == 0 else {
            throw CellarError.ioFailure("Couldn't start Wine from \(executable.path): \(String(cString: strerror(status)))")
        }
        let child = pid
        DispatchQueue.global(qos: .utility).async {
            var exitStatus: Int32 = 0
            _ = waitpid(child, &exitStatus, 0)
        }
    }

    public func wineVersion() -> String {
        run(["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Overrides that keep `wineboot` from putting anything on screen. Mono and Gecko would offer
    /// to install themselves; the Mac graphics driver would show Wine's own "Please wait… the Wine
    /// configuration is being updated" box — a window with a wine glass on it, in the middle of
    /// Cellar, that the player can do nothing with. With `winemac.drv` disabled Wine falls back to
    /// its null display driver, so the box is drawn nowhere. WineForge ignores the
    /// `WINEBOOT_HIDE_DIALOG` that Proton honours, which is why this is done with the driver.
    ///
    /// Only for `wineboot`, and only with the server waited out afterwards: a Windows program
    /// started into a session whose desktop has the null driver would have invisible windows. The
    /// next session loads the real driver and registers the real GPU and displays again.
    static let headlessBootOverrides = "mscoree=d;mshtml=d;winemac.drv=d"

    /// Create the prefix, with nothing on screen while it happens (`headlessBootOverrides`).
    /// A wow64 Wine build (Sikarugir) produces both `Program Files` trees, which the 32-bit Steam
    /// client + 64-bit games need.
    ///
    /// Returns the home folders that had to be redirected into the bottle because macOS refuses
    /// Cellar access to them — empty on the normal path. `wineboot` points the Windows user's
    /// Documents/Desktop/Downloads at the real ones, so a folder the player declined would leave a
    /// game writing saves into a symlink it cannot follow (see `HomeFolderAccess`).
    ///
    /// `checkingHomeFolders: false` skips that check, which reads the folders and so can make macOS
    /// ask for them — right for a bottle no game will run in (`Preparation`'s scaffold), which must
    /// not put a permission dialog in front of a player who is still reading the welcome tour.
    @discardableResult
    public func initializePrefix(checkingHomeFolders: Bool = true) throws -> [HomeFolder] {
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let result = run(["wineboot", "--init"], extraEnv: ["WINEDLLOVERRIDES": Self.headlessBootOverrides])
        guard result.succeeded else {
            throw CellarError.ioFailure("wineboot --init failed: \(result.stderr)")
        }
        waitForServer()
        guard checkingHomeFolders else { return [] }
        return HomeFolderAccess.redirectDeniedUserShellFolders(in: prefix)
    }

    /// Wine rebuilds a prefix whenever the runner's `wine.inf` differs from the one the prefix was
    /// built from — after a runner update — and it does so *on the next launch*, with the same
    /// "Please wait" box on screen. Doing it here first, headless, leaves that launch nothing to do.
    /// On the normal path this is one stat and one small read.
    public func updatePrefixIfStale() {
        guard let inf = wineInf, PrefixFreshness.needsUpdate(prefix: prefix, wineInf: inf),
              !serverRunning else { return }
        CellarLog.info(.runner, "Updating bottle '\(prefix.lastPathComponent)' for the new runner.",
                       subject: prefix.lastPathComponent)
        SaveBackups.backUpQuietly(bottle: prefix, reason: .beforeRunnerUpdate)
        run(["wineboot", "--update"], extraEnv: ["WINEDLLOVERRIDES": Self.headlessBootOverrides])
        waitForServer()
    }

    /// The `wine.inf` this runner builds prefixes from.
    private var wineInf: URL? {
        let root = install?.wineRoot ?? binary.deletingLastPathComponent().deletingLastPathComponent()
        let inf = root.appendingPathComponent("share/wine/wine.inf")
        return FileManager.default.fileExists(atPath: inf.path) ? inf : nil
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

    /// Take this bottle's Wine down and make sure it stayed down.
    ///
    /// `wineserver -k` asks the server to end every Windows process in the prefix, and on its own it
    /// was trusted to: Planet Coaster 2 was quit and three `wine` processes were still in Activity
    /// Monitor afterwards. So the server gets a few seconds, then `-k9`, and whatever still runs the
    /// runner's own binaries once no server of this runner is left is stopped too.
    ///
    /// Returns the processes that had to be swept up — empty when Wine went down on its own.
    @discardableResult
    public func shutDown(grace: TimeInterval = 10) -> [pid_t] {
        let bottle = prefix.lastPathComponent
        killServer()
        if !waitForServerToStop(within: grace) {
            CellarLog.warn(.session, "wineserver for \(bottle) was still up \(Int(grace))s after -k; killing it.")
            if FileManager.default.fileExists(atPath: wineserver.path) {
                Shell.run(wineserver.path, ["-k9"], environment: environment())
            }
            _ = waitForServerToStop(within: 3)
        }
        let swept = RunnerProcesses.sweep(root: runnerRoot)
        if !swept.isEmpty {
            CellarLog.warn(.session, "Stopped \(swept.count) Wine process(es) that outlived \(bottle)'s "
                + "wineserver: \(swept.map { "\($0)" }.joined(separator: ", ")).")
        }
        return swept
    }

    /// Poll until this prefix's wineserver is gone. False if it is still there at the deadline.
    private func waitForServerToStop(within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while serverRunning {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return true
    }

    /// The runner's own directory: every Wine process of every bottle on it runs a binary in here.
    private var runnerRoot: URL {
        install?.wineRoot ?? binary.deletingLastPathComponent().deletingLastPathComponent()
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

/// Wine's own test for "this prefix needs updating", made without starting Wine.
///
/// `wineboot` writes the modification time of the `wine.inf` it applied into
/// `<prefix>/.update-timestamp`; every Wine process started afterwards compares the two and rebuilds
/// the prefix when they differ. The file may also say `disable`, which turns the check off.
public enum PrefixFreshness {
    public static func needsUpdate(prefix: URL, wineInf: URL) -> Bool {
        // No registry means no prefix yet — building one is `initializePrefix`'s job, not an update.
        guard FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: wineInf.path),
              let modified = attributes[.modificationDate] as? Date else { return false }
        guard let recorded = try? String(contentsOf: prefix.appendingPathComponent(".update-timestamp"),
                                         encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
        if recorded == "disable" { return false }
        return recorded != String(Int(modified.timeIntervalSince1970))
    }
}
