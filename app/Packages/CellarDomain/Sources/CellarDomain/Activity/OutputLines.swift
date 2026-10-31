import Foundation

/// Turns a command's raw output, read in whatever pieces the pipe hands over, into whole lines.
///
/// Bytes, not strings: a pipe can split a multi-byte character across two reads, and decoding each
/// read on its own dropped the whole read when that happened. Newlines and carriage returns are
/// single bytes that never occur inside a multi-byte character, so splitting on them before
/// decoding is safe.
///
/// A line redrawn with `\r` (a terminal progress bar) keeps only what a terminal would end up
/// showing: the text after the last carriage return.
public struct OutputLines: Sendable {
    /// Bytes after the last newline, waiting for the rest of their line.
    private var pending: [UInt8] = []
    /// How much may wait without a newline before the redrawn part of it is let go. A tool that
    /// only ever redraws one line would otherwise grow this for the length of the download.
    public static let pendingLimit = 64 * 1024

    public init() {}

    /// The complete lines in `data`, after whatever earlier reads left unfinished.
    public mutating func lines(in data: Data) -> [String] {
        pending += data
        guard let last = pending.lastIndex(of: Self.newline) else {
            trimPending()
            return []
        }
        let complete = pending[pending.startIndex..<last]
        let lines = complete.split(separator: Self.newline, omittingEmptySubsequences: false).map(Self.line)
        pending.removeSubrange(pending.startIndex...last)
        return lines
    }

    /// The unfinished line as it stands, for showing before its newline arrives.
    public var partial: String { Self.line(pending[...]) }

    /// Whatever is left, as a last line — for when the command has exited. Nil when nothing is.
    public mutating func finish() -> String? {
        defer { pending.removeAll() }
        let rest = partial
        return rest.isEmpty ? nil : rest
    }

    private mutating func trimPending() {
        guard pending.count > Self.pendingLimit else { return }
        if let cr = pending.lastIndex(of: Self.carriageReturn) {
            pending.removeSubrange(pending.startIndex...cr)
        }
        if pending.count > Self.pendingLimit {
            pending.removeFirst(pending.count - Self.pendingLimit)
        }
    }

    /// One line's bytes as text: a trailing `\r` (from `\r\n`) dropped, and anything redrawn over.
    static func line(_ bytes: ArraySlice<UInt8>) -> String {
        var slice = bytes
        if slice.last == carriageReturn { slice = slice.dropLast() }
        if let cr = slice.lastIndex(of: carriageReturn) { slice = slice[slice.index(after: cr)...] }
        return String(decoding: slice, as: UTF8.self)
    }

    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
}
