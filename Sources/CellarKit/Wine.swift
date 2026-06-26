import Foundation

/// Drives a Wine runner against a specific prefix. Always launches via `/usr/bin/arch -x86_64`
/// so the x86_64 Wine binaries run under Rosetta 2 even from an arm64 parent.
public struct WineRunner {
    public let binary: URL    // wine (Wine 11) or wine64 (GPTK)
    public let prefix: URL    // WINEPREFIX

    public init(binary: URL, prefix: URL) {
        self.binary = binary
        self.prefix = prefix
    }

    public init(install: RunnerInstall, prefix: URL) {
        self.init(binary: install.wineBinary, prefix: prefix)
    }

    /// Base environment. msync is the preferred fast sync on macOS; esync is the fallback.
    public func environment(extra: [String: String] = [:]) -> [String: String] {
        var env: [String: String] = [
            "WINEPREFIX": prefix.path,
            "WINEDEBUG": "-all",
            "WINEESYNC": "1",
            "WINEMSYNC": "1",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        ]
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// Run wine with arguments. `inheritIO` lets GUIs/long-running processes draw and stream output.
    @discardableResult
    public func run(_ args: [String], extraEnv: [String: String] = [:], inheritIO: Bool = false) -> Shell.Result {
        let env = environment(extra: extraEnv)
        let archArgs = ["-x86_64", binary.path] + args

        if !inheritIO {
            return Shell.run("/usr/bin/arch", archArgs, environment: env)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = archArgs
        process.environment = env
        do { try process.run() } catch {
            return Shell.Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        process.waitUntilExit()
        return Shell.Result(exitCode: process.terminationStatus, stdout: "", stderr: "")
    }

    public func wineVersion() -> String {
        run(["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create the prefix. Suppresses the Mono/Gecko first-run dialogs so init is headless.
    public func initializePrefix() throws {
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let result = run(["wineboot", "--init"], extraEnv: ["WINEDLLOVERRIDES": "mscoree=d;mshtml=d"])
        guard result.succeeded else {
            throw CellarError.ioFailure("wineboot --init failed: \(result.stderr)")
        }
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

    /// Stop wineserver (e.g. before deleting a prefix).
    public func killServer() {
        let server = binary.deletingLastPathComponent().appendingPathComponent("wineserver")
        if FileManager.default.fileExists(atPath: server.path) {
            Shell.run("/usr/bin/arch", ["-x86_64", server.path, "-k"], environment: environment())
        }
    }

    /// Environment that activates Apple's D3DMetal niceties for a GPTK runner.
    /// D3DMetal itself needs NO WINEDLLOVERRIDES — it's the builtin renderer in the GPTK Wine build.
    public static func d3dMetalEnv(showHUD: Bool = false) -> [String: String] {
        var env = [
            "D3DM_SUPPORT_DXR": "1",        // ray-tracing translation where supported
            "ROSETTA_ADVERTISE_AVX": "1",   // expose AVX/AVX2 to translated games (macOS 15+)
            "WINEMSYNC": "1",
            "WINEESYNC": "1",
        ]
        if showHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
    }
}
