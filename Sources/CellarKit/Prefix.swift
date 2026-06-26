import Foundation

/// Graphics translation backend selected per bottle/profile.
public enum GraphicsBackend: String, CaseIterable {
    case d3dmetal   // Apple D3DMetal: DX11/12 -> Metal (fastest for modern games; user-supplied)
    case dxvk       // DXVK: DX9/10/11 -> Vulkan (-> MoltenVK)
    case vkd3d      // VKD3D-Proton: DX12 -> Vulkan (-> MoltenVK)
    case wined3d    // Wine's built-in DX -> OpenGL
    case dxmt       // Community DX11 -> Metal
}

public struct PrefixInfo {
    public let name: String
    public let url: URL
    public let backend: String
    public let runner: String
}

/// Manages bottles: one isolated WINEPREFIX + a `bottle.toml` per game.
public enum PrefixManager {
    public static func list() throws -> [PrefixInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.prefixes.path) else { return [] }
        let entries = try fm.contentsOfDirectory(at: Paths.prefixes, includingPropertiesForKeys: [.isDirectoryKey])
        return entries.compactMap { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let config = readBottleConfig(url.appendingPathComponent("bottle.toml"))
            return PrefixInfo(
                name: url.lastPathComponent,
                url: url,
                backend: config["backend"] ?? "unset",
                runner: config["runner"] ?? "unset")
        }.sorted { $0.name < $1.name }
    }

    @discardableResult
    public static func create(name: String, backend: GraphicsBackend, runner: String) throws -> PrefixInfo {
        try Paths.ensureBaseDirectories()
        let url = Paths.prefixes.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else {
            throw CellarError.invalidArgument("A bottle named '\(name)' already exists at \(url.path)")
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("pfx", isDirectory: true), withIntermediateDirectories: true)

        let bottle = """
        # Cellar bottle configuration — \(name)
        name = "\(name)"
        backend = "\(backend.rawValue)"
        runner = "\(runner)"
        windows_version = "win10"

        [env]
        # Per-bottle environment overrides, e.g.:
        # MTL_HUD_ENABLED = "1"

        [dll_overrides]
        # e.g. "d3d11" = "native,builtin"
        """
        try bottle.write(to: url.appendingPathComponent("bottle.toml"), atomically: true, encoding: .utf8)
        return PrefixInfo(name: name, url: url, backend: backend.rawValue, runner: runner)
    }

    public static func remove(name: String) throws {
        let url = Paths.prefixes.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CellarError.invalidArgument("No bottle named '\(name)'")
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Tiny key="value" reader for top-level scalars. Full TOML decoding arrives with the
    /// profile loader in Phase 2; this is enough to display a bottle's backend/runner.
    static func readBottleConfig(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var dict: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), !line.hasPrefix("["), line.contains("=") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            dict[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return dict
    }
}
