import Foundation

public enum CheckStatus: String {
    case ok, warn, fail, info
}

public struct CheckResult {
    public let name: String
    public let status: CheckStatus
    public let detail: String
    public let hint: String?

    public init(_ name: String, _ status: CheckStatus, _ detail: String, hint: String? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.hint = hint
    }
}

/// Detects whether the host Mac is ready to translate Windows games, and powers `cellar doctor`.
public enum SystemEnvironment {
    public static var isAppleSilicon: Bool {
        Shell.run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    public static var chipBrand: String {
        Shell.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static var macOSVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    public static var macOSVersionString: String {
        let v = macOSVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Rosetta is considered functional if an x86_64 process can actually run.
    public static var rosettaWorks: Bool {
        guard isAppleSilicon else { return false }
        return Shell.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).succeeded
    }

    public static var armHomebrew: String? { fileIfExists("/opt/homebrew/bin/brew") }
    public static var x86Homebrew: String? { fileIfExists("/usr/local/bin/brew") }

    public static var d3dmetalImported: Bool {
        FileManager.default.fileExists(
            atPath: Paths.d3dmetalCache.appendingPathComponent("D3DMetal.framework").path)
    }

    public static func freeDiskGB() -> Double? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Double(bytes) / 1_000_000_000
    }

    private static func fileIfExists(_ path: String) -> String? {
        FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Reports what the installed runners are actually built for, and how that lands against the
    /// Rosetta timeline: full Rosetta through macOS 27, gaming-only subset from macOS 28 (2027).
    static func runnerArchitectureCheck(macOSMajor: Int) -> CheckResult {
        let installed = RunnerManager.installed()
        guard !installed.isEmpty else {
            return .init("Runner arch", .info, "no runner installed",
                hint: "Install one: cellar runner install \(RunnerCatalog.defaultID)")
        }

        let rosettaBound = installed.filter(\.needsRosetta)
        let native = installed.filter { !$0.needsRosetta }
        let summary = installed
            .map { "\($0.spec.id)=\($0.needsRosetta ? "x86_64" : "arm64ec")" }
            .joined(separator: ", ")

        if rosettaBound.isEmpty {
            return .init("Runner arch", .ok, summary,
                hint: "Native ARM64EC runner — independent of Rosetta. The game's own x86-64 code "
                    + "is translated inside the layer.")
        }
        if !native.isEmpty {
            return .init("Runner arch", .ok, summary,
                hint: "A native ARM64EC runner is installed alongside x86_64 ones; prefer it from "
                    + "macOS 28 on (profiles can pin a runner).")
        }
        if macOSMajor >= 28 {
            return .init("Runner arch", .warn, summary,
                hint: "Every installed runner is x86_64 and general Rosetta is gone in macOS \(macOSMajor). "
                    + "These now rely on Apple's gaming-only Rosetta subset, which is not guaranteed "
                    + "to cover a Wine layer. Migration target: a native ARM64EC runner (FEX).")
        }
        return .init("Runner arch", .info, summary,
            hint: "x86_64 under Rosetta 2 — fine through macOS 27. Tracked migration: a native "
                + "ARM64EC + FEX runner, see docs/ROADMAP.md Phase 5.")
    }

    /// The full diagnostic battery printed by `cellar doctor`.
    public static func diagnostics() -> [CheckResult] {
        var checks: [CheckResult] = []

        // Apple Silicon
        if isAppleSilicon {
            checks.append(.init("Apple Silicon", .ok, chipBrand.isEmpty ? "arm64" : chipBrand))
        } else {
            checks.append(.init("Apple Silicon", .fail, "Intel Mac (\(chipBrand))",
                hint: "The D3DMetal path requires Apple Silicon. Intel Macs are limited to the DXVK/MoltenVK path."))
        }

        // macOS version
        let version = macOSVersion
        if version.majorVersion >= 14 {
            checks.append(.init("macOS", .ok, "macOS \(macOSVersionString)"))
        } else {
            checks.append(.init("macOS", .warn, "macOS \(macOSVersionString)",
                hint: "Apple's Game Porting Toolkit (D3DMetal) needs macOS 14 (Sonoma) or later."))
        }

        // Rosetta 2 (with the Intel-app/Rosetta-sunset horizon surfaced)
        if !isAppleSilicon {
            checks.append(.init("Rosetta 2", .info, "n/a on Intel"))
        } else if !rosettaWorks {
            checks.append(.init("Rosetta 2", .fail, "not installed",
                hint: "Install with: softwareupdate --install-rosetta --agree-to-license"))
        } else if version.majorVersion >= 28 {
            checks.append(.init("Rosetta 2", .warn, "general Rosetta removed in macOS \(version.majorVersion)",
                hint: "An x86_64 runner now depends on Apple's retained gaming-only Rosetta subset. "
                    + "Prefer a native ARM64EC runner if one is available (cellar runner list)."))
        } else {
            checks.append(.init("Rosetta 2", .ok, "installed & functional",
                hint: "macOS may show an 'Intel app support ending' notice for the runner — harmless: "
                    + "Rosetta works through macOS 27, and Apple keeps a gaming subset after."))
        }

        // Runner architecture — the thing that actually decides whether the sunset bites.
        // Measured from the installed wine binary, not taken from the catalog's word for it.
        checks.append(runnerArchitectureCheck(macOSMajor: version.majorVersion))

        // The Dock shim. Cosmetic, so never a failure — but say so plainly rather than let a
        // storefront client quietly turn up in the Dock with no explanation.
        if let shim = DockShim.libraryURL {
            checks.append(.init("Dock shim", .ok, shim.path))
        } else {
            checks.append(.init("Dock shim", .info, "not built",
                hint: "A bottle's Steam/Battle.net will show its own Dock icon while you play. "
                    + "Build it with: sh Scripts/build-dock-shim.sh"))
        }

        // Homebrew (arm)
        if let brew = armHomebrew {
            checks.append(.init("Homebrew (arm64)", .ok, brew))
        } else {
            checks.append(.init("Homebrew (arm64)", .warn, "not found",
                hint: "Install from https://brew.sh"))
        }

        // Homebrew (x86_64) — only relevant if building GPTK/Wine from source under Rosetta.
        if let brew = x86Homebrew {
            checks.append(.init("Homebrew (x86_64)", .ok, brew))
        } else {
            checks.append(.init("Homebrew (x86_64)", .info, "not found",
                hint: "Only needed to build GPTK/Wine from source. Prebuilt runners don't require it."))
        }

        // git
        if let git = Shell.which("git") {
            checks.append(.init("git", .ok, git))
        } else {
            checks.append(.init("git", .warn, "not found"))
        }

        // gh (optional, used for repo workflows)
        if let gh = Shell.which("gh") {
            let auth = Shell.run(gh, ["auth", "status"])
            if auth.succeeded {
                checks.append(.init("gh (GitHub CLI)", .ok, "authenticated"))
            } else {
                checks.append(.init("gh (GitHub CLI)", .warn, "installed, not authenticated",
                    hint: "Run: gh auth login -h github.com"))
            }
        } else {
            checks.append(.init("gh (GitHub CLI)", .info, "not found",
                hint: "Optional; only used for repo workflows."))
        }

        // Default runner (Wine 10 + Apple D3DMetal 3.0) — the modern-DX path
        let defaultID = RunnerCatalog.defaultID
        if let runner = RunnerManager.find(id: defaultID) {
            let d3d = runner.renderer("d3dmetal") != nil ? "D3DMetal present" : "D3DMetal MISSING"
            checks.append(.init("Runner (\(defaultID))", .ok, "installed — \(d3d)"))
        } else {
            checks.append(.init("Runner (\(defaultID))", .info, "not installed",
                hint: "Install it with: cellar runner install \(defaultID)   (or just run: cellar setup)"))
        }
        if RunnerManager.find(id: "gptk") != nil {
            checks.append(.init("Runner (gptk)", .warn, "installed but deprecated",
                hint: RunnerCatalog.gptk.deprecated ?? ""))
        }

        // Disk
        if let gb = freeDiskGB() {
            let status: CheckStatus = gb < 30 ? .warn : .ok
            checks.append(.init("Free disk", status, String(format: "%.0f GB available", gb),
                hint: status == .warn ? "A game plus a Windows Steam bottle can need 30–100 GB." : nil))
        }

        return checks
    }
}
