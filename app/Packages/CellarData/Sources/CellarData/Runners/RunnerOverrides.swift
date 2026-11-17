import CellarDomain
import Foundation

/// A player's own files for a catalog runner: `runner-artifacts.json` in Cellar's folder.
///
/// Whoever builds Wine themselves, or takes a renderer from its own upstream release, names the
/// files here, each with its SHA-256, and that runner is installed, checked and repaired from them:
///
///     { "wineforge": [
///         { "kind": "wineEngine", "source": "/Users/me/builds/wine.tar.xz",
///           "payloadPath": "wine", "sha256": "…" },
///         { "kind": "wrapperFrameworks", "source": "/Users/me/builds/frameworks.tar.xz",
///           "payloadPath": "Frameworks", "sha256": "…" } ] }
///
/// The list replaces the catalog's for that runner, whole: nothing the catalog names is downloaded
/// unless it is named here too. A `source` is an absolute path, read in place and never deleted, or
/// an `https://` URL, fetched and cached like the catalog's. `kind` and `payloadPath` mean what
/// they do in `RunnerArtifact`. A runner already installed stays until it is removed or needs
/// repairing (a `wineserver` named here that it doesn't run counts); either way it is then
/// installed from these files.
enum RunnerOverrides {
    static var file: URL { Paths.appSupport.appendingPathComponent("runner-artifacts.json") }

    struct Entry: Decodable {
        let kind: String
        let source: String
        let payloadPath: String?
        let sha256: String
    }

    /// `spec` with the artifacts the file names for it, or `spec` itself when there is no file or
    /// it leaves this runner alone. A file that can't be read as described leaves the runner with
    /// nothing to install, said in the log: a typo must never mean the catalog's downloads after all.
    static func applied(to spec: RunnerSpec, file: URL = file) -> RunnerSpec {
        guard let data = try? Data(contentsOf: file) else { return spec }
        var spec = spec
        do {
            guard let entries = try JSONDecoder().decode([String: [Entry]].self, from: data)[spec.id] else {
                return spec
            }
            spec.artifacts = try entries.map(artifact)
        } catch {
            CellarLog.error(.runner, "\(file.path) can't be used: \(CellarLog.describe(error))", subject: spec.id)
            spec.artifacts = []
        }
        return spec
    }

    static func artifact(_ entry: Entry) throws -> RunnerArtifact {
        guard let kind = RunnerArtifact.Kind(rawValue: entry.kind) else {
            throw CellarError.invalidArgument("'\(entry.kind)' is not a kind of runner artifact")
        }
        guard entry.source.hasPrefix("/") || entry.source.hasPrefix("https://") else {
            throw CellarError.invalidArgument("'\(entry.source)' is neither an absolute path nor an https:// URL")
        }
        guard Checksum.isWellFormed(entry.sha256) else {
            throw CellarError.invalidArgument("the sha256 of '\(entry.source)' is not 64 lowercase hex characters")
        }
        return RunnerArtifact(kind: kind, url: entry.source, payloadPath: entry.payloadPath ?? "", sha256: entry.sha256)
    }
}
