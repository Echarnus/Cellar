import Foundation

/// The checkout the tests are running out of.
///
/// Cellar's profile database is *data in the repo*, not a fixture invented for the tests — the whole
/// point of testing it is to catch a real profile that a player would then hit. `#filePath` is fixed
/// at compile time and this file's location in the package is fixed too, so walking up from it finds
/// the checkout without depending on the working directory a runner happens to use.
enum Repo {
    static let root: URL = URL(fileURLWithPath: #filePath)   // app/tests/CellarDataTests/RepoRoot.swift
        .deletingLastPathComponent()                          // app/tests/CellarDataTests
        .deletingLastPathComponent()                          // app/tests
        .deletingLastPathComponent()                          // app
        .deletingLastPathComponent()                          // <checkout>

    /// The Swift package: `Package.swift`, `src/`, `tests/`, `Resources/` and the app's scripts.
    /// The checkout root holds what the app and the site share: profiles, licences, `.github/`.
    static var app: URL { root.appendingPathComponent("app", isDirectory: true) }

    /// The local package each library lives in (`app/Packages/<package>/Sources/<target>`). The
    /// executables are the app shell's own targets, in `app/src/<target>`.
    static let packageOfLibrary = ["CellarDomain": "CellarDomain", "CellarData": "CellarData",
                                   "CellarInfrastructure": "CellarData", "CellarUI": "CellarUI"]

    /// A path inside a target's sources, written as `<Target>/<rest>`: `CellarData/UseCases`.
    static func source(_ path: String) -> URL {
        let target = String(path.split(separator: "/").first ?? "")
        if let package = packageOfLibrary[target] {
            return app.appendingPathComponent("Packages/\(package)/Sources/\(path)")
        }
        return app.appendingPathComponent("src/\(path)")
    }

    static var profiles: URL { root.appendingPathComponent("profiles", isDirectory: true) }

    /// Every `profiles/*.toml` in the checkout, sorted, so a failure names the same profile twice
    /// in a row rather than moving around between runs.
    static func profileFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "toml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
