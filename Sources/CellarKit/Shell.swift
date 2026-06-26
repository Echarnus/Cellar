import Foundation

/// Small wrapper around `Process` for running external tools and capturing output.
/// Intentionally synchronous — Cellar's CLI runs one step at a time.
public enum Shell {
    public struct Result {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
        public var succeeded: Bool { exitCode == 0 }
    }

    @discardableResult
    public static func run(
        _ executable: String,
        _ args: [String] = [],
        environment: [String: String]? = nil
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Outputs here are small (version strings, paths); read-then-wait is fine.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Resolve an executable on PATH (like `which`).
    public static func which(_ name: String) -> String? {
        let result = run("/usr/bin/which", [name])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && !path.isEmpty ? path : nil
    }
}
