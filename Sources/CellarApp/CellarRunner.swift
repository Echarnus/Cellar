import Foundation
import CellarKit

/// Drives the `cellar` CLI as a subprocess so the GUI reuses every tested code path (setup, launch
/// with its auto-retry, steam add) instead of reimplementing them. Streams combined output.
@MainActor
final class CellarRunner: ObservableObject {
    @Published var log: String = ""
    @Published var busy: Bool = false
    @Published var busyTitle: String = ""

    private let binary: String

    init() {
        // Prefer a `cellar` on PATH; fall back to the common install location.
        binary = Shell.which("cellar") ?? "\(NSHomeDirectory())/.local/bin/cellar"
    }

    var binaryExists: Bool { FileManager.default.isExecutableFile(atPath: binary) }

    func run(_ args: [String], title: String, then: (@MainActor () -> Void)? = nil) {
        guard !busy else { return }
        busy = true; busyTitle = title
        log += "\n$ cellar \(args.joined(separator: " "))\n"

        Task.detached { [binary] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self.log += s }
            }
            try? process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            await MainActor.run {
                self.log += "\n(exit \(process.terminationStatus))\n"
                self.busy = false
                then?()
            }
        }
    }
}
