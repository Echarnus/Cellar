import CellarDomain
import Foundation
import Testing

/// `OutputLines` and `LogTail`: how a command's output becomes the activity log. A download prints
/// a line per file, and the app used to keep and re-lay-out all of them on every read (#166).
@Suite("Command output")
struct OutputLinesTests {

    @Test("Lines come out whole, however the pipe cut them")
    func linesAcrossReads() {
        var lines = OutputLines()
        let r1 = lines.lines(in: Data("first li".utf8))
        #expect(r1.isEmpty)
        #expect(lines.partial == "first li")
        let r2 = lines.lines(in: Data("ne\nsecond\nthi".utf8))
        #expect(r2 == ["first line", "second"])
        #expect(lines.partial == "thi")
        let r3 = lines.lines(in: Data("rd\n".utf8))
        #expect(r3 == ["third"])
        #expect(lines.partial.isEmpty)
    }

    @Test("A character split across two reads arrives intact, not dropped")
    func multibyteSplit() {
        var lines = OutputLines()
        let bytes = Array("Café ✓\n".utf8)
        // Cut inside the three bytes of "✓".
        let cut = bytes.count - 3
        let r4 = lines.lines(in: Data(bytes[..<cut]))
        #expect(r4.isEmpty)
        let r5 = lines.lines(in: Data(bytes[cut...]))
        #expect(r5 == ["Café ✓"])
    }

    @Test("CRLF ends a line, and a redrawn line keeps only what a terminal would show")
    func carriageReturns() {
        var lines = OutputLines()
        let r6 = lines.lines(in: Data("windows\r\n 10%\r 20%\r 30%\n".utf8))
        #expect(r6 == ["windows", " 30%"])
        _ = lines.lines(in: Data(" 40%\r 50%".utf8))
        #expect(lines.partial == " 50%")
    }

    @Test("What never got its newline is handed over at the end, once")
    func finish() {
        var lines = OutputLines()
        _ = lines.lines(in: Data("no newline".utf8))
        let r7 = lines.finish()
        #expect(r7 == "no newline")
        let r8 = lines.finish()
        #expect(r8 == nil)
    }

    @Test("A line that is only ever redrawn cannot grow without end")
    func pendingIsBounded() {
        var lines = OutputLines()
        for i in 0..<20_000 { _ = lines.lines(in: Data(" \(i)% file\r".utf8)) }
        #expect(lines.partial.utf8.count <= OutputLines.pendingLimit)
        let r9 = lines.lines(in: Data("\n".utf8))
        #expect(r9.count == 1)
    }

    // MARK: - LogTail

    @Test("The log keeps the last lines and says how many it let go")
    func tailKeepsTheEnd() {
        var tail = LogTail(limit: 3)
        for i in 1...10 { tail.append("line \(i)") }
        #expect(Array(tail.kept) == ["line 8", "line 9", "line 10"])
        #expect(tail.total == 10)
        let text = tail.text(partial: "still writing")
        #expect(text.hasSuffix("line 8\nline 9\nline 10\nstill writing"))
        #expect(text.contains("7"), "the note says how many lines are hidden: \(text)")
    }

    @Test("A short log reads exactly as it was printed")
    func tailUntrimmed() {
        var tail = LogTail(limit: 100)
        tail.append("$ cellar install game")
        tail.append("Installed.")
        #expect(tail.text() == "$ cellar install game\nInstalled.\n")
        #expect(tail.dropped == 0)
    }

    @Test("A download's worth of lines stays a log you can lay out")
    func tailStaysSmall() {
        var tail = LogTail(limit: 1_000)
        for i in 0..<100_000 { tail.append(" \(i % 100).00% game\\data\\file\(i).pak") }
        #expect(tail.kept.count == 1_000)
        #expect(tail.text().count < 100_000, "a thousand lines, not a hundred thousand")
    }

    @Test("A runaway line is cut")
    func longLine() {
        var tail = LogTail(limit: 2)
        tail.append(String(repeating: "x", count: LogTail.lineLimit * 3))
        #expect(tail.kept.first!.count == LogTail.lineLimit + 1)
    }
}
