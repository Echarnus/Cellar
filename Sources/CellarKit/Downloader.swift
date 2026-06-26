import Foundation

/// Downloads files via curl (handles redirects, large files, and shows a live progress bar on a TTY).
public enum Downloader {
    /// Fetch `url` to `destination`. Creates parent directories as needed.
    @discardableResult
    public static func fetch(_ url: String, to destination: URL, showProgress: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Inherit stdio (no pipes) so curl's progress bar renders live.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            showProgress ? "--progress-bar" : "-s",
            "-L",            // follow redirects
            "--fail",        // non-zero exit on HTTP errors
            "-o", destination.path,
            url,
        ]

        do {
            try process.run()
        } catch {
            throw CellarError.ioFailure("Could not start curl: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CellarError.ioFailure("Download failed (curl exit \(process.terminationStatus)) for \(url)")
        }
        return destination
    }

    /// Fetch a URL and return its body as a String (for small API/JSON responses).
    public static func string(_ url: String) throws -> String {
        let result = Shell.run("/usr/bin/curl", ["-sL", "--fail", url])
        guard result.succeeded else {
            throw CellarError.ioFailure("Request failed for \(url): \(result.stderr)")
        }
        return result.stdout
    }
}
