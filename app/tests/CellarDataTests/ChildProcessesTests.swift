import Foundation
import Testing
@testable import CellarData

/// The tools a `cellar` command starts stop when it is stopped (#166). A cancelled download used to
/// leave DepotDownloader fetching on its own, and the Mac stayed slow after the download was "over".
@Suite(.serialized)
struct ChildProcessesTests {

    func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    @Test("A followed tool is stopped, and no longer followed")
    func terminateAll() throws {
        let process = try sleeper()
        ChildProcesses.track(process)
        #expect(ChildProcesses.count >= 1)
        let stillRunning = ChildProcesses.terminateAll()
        #expect(stillRunning == 0)
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal, "it was stopped, not left to finish")
        #expect(ChildProcesses.count == 0)
    }

    @Test("A tool that ended on its own is let go and not signalled")
    func untrack() throws {
        let process = try sleeper()
        ChildProcesses.track(process)
        ChildProcesses.untrack(process)
        #expect(ChildProcesses.terminateAll(grace: 0) == 0)
        #expect(process.isRunning, "an untracked process is none of terminateAll's business")
        process.terminate()
        process.waitUntilExit()
    }

    // MARK: - DepotTool's line splitter

    @Test("DepotDownloader's output is split on both line ends, and the rest waits for the next read")
    func takeLines() {
        var buffer = Data(" 1.00% a.pak\r 2.00% b.pak\nDownloading de".utf8)
        let r1 = DepotTool.takeLines(from: &buffer)
        #expect(r1 == [" 1.00% a.pak", " 2.00% b.pak"])
        #expect(String(decoding: buffer, as: UTF8.self) == "Downloading de")
        buffer.append(Data("pot\n".utf8))
        let r2 = DepotTool.takeLines(from: &buffer)
        #expect(r2 == ["Downloading depot"])
        #expect(buffer.isEmpty)
    }

    @Test("Thousands of lines in one read split in one pass")
    func takeLinesAtScale() {
        var text = ""
        for i in 0..<20_000 { text += " \(i % 100).00% file\(i).pak\n" }
        var buffer = Data(text.utf8)
        let r3 = DepotTool.takeLines(from: &buffer)
        #expect(r3.count == 20_000)
        #expect(buffer.isEmpty)
    }
}
