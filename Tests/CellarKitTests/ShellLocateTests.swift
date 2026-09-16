import Foundation
import Testing
@testable import CellarKit

/// `Shell.locate` is what the app uses to find the CLI from inside a view body, where starting a
/// process froze the window on macOS 27. It has to agree with `which` without running it.
struct ShellLocateTests {

    @Test("Finds the first executable match on PATH, in PATH order")
    func firstExecutableWins() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shell-locate-\(UUID().uuidString)")
        let first = root.appendingPathComponent("a"), second = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Present but not executable in the first directory: skipped, like `which` does.
        FileManager.default.createFile(atPath: first.appendingPathComponent("tool").path, contents: Data())
        FileManager.default.createFile(atPath: second.appendingPathComponent("tool").path, contents: Data(),
                                       attributes: [.posixPermissions: 0o755])

        let path = "\(first.path)::\(second.path)"
        #expect(Shell.locate("tool", path: path) == second.appendingPathComponent("tool").path)
        #expect(Shell.locate("missing", path: path) == nil)
        #expect(Shell.locate("tool", path: nil) == nil)
    }

    @Test("Finds a real system tool")
    func findsSystemTool() {
        #expect(Shell.locate("ls", path: "/usr/bin:/bin") == "/bin/ls")
    }
}
