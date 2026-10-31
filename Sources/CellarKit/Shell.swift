import CellarDomain
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
        environment: [String: String]? = nil,
        input: Data? = nil
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // `input` is for what must not be on a command line (any process can read another's argv):
        // a secret is handed over on stdin instead. Small, so writing before reading cannot block.
        let inPipe = input.map { _ in Pipe() }
        if let inPipe { process.standardInput = inPipe }

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        if let inPipe, let input {
            try? inPipe.fileHandleForWriting.write(contentsOf: input)
            try? inPipe.fileHandleForWriting.close()
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

    /// Resolve an executable on PATH **without starting a process** — safe to call from a view
    /// body, where `which` (and the run loop its `waitUntilExit` spins) is not.
    public static func locate(_ name: String,
                              path: String? = ProcessInfo.processInfo.environment["PATH"]) -> String? {
        guard let path else { return nil }
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Resolve an executable on PATH (like `which`).
    public static func which(_ name: String) -> String? {
        let result = run("/usr/bin/which", [name])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && !path.isEmpty ? path : nil
    }
}
