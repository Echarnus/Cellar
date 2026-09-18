import Foundation

/// Steam's text key-values format (`config.vdf`, `loginusers.vdf`, `local.vdf`): quoted keys, each
/// followed by either a quoted string or a `{ … }` block. Order and duplicates are kept, so a file
/// Cellar edits reads back exactly as Steam wrote it apart from the keys that were changed.
struct TextVDF: Equatable {
    indirect enum Value: Equatable {
        case string(String)
        case block(TextVDF)
    }

    struct Entry: Equatable {
        var key: String
        var value: Value
        /// The value exactly as the file spelled it, escapes and all. Re-emitted verbatim, so a value
        /// Cellar did not touch cannot come back altered — `config.vdf` is rewritten whole, and Valve
        /// writes escapes Cellar has no business reinterpreting.
        var rawValue: String?

        init(key: String, value: Value, rawValue: String? = nil) {
            self.key = key
            self.value = value
            self.rawValue = rawValue
        }
    }

    var entries: [Entry] = []

    // MARK: - Reading

    /// `nil` for anything that isn't well-formed — a file Cellar can't read is a file it must not
    /// rewrite.
    static func parse(_ text: String) -> TextVDF? {
        var scanner = Scanner(Array(text.unicodeScalars))
        guard let root = scanner.block(closed: false), scanner.atEnd else { return nil }
        return root
    }

    subscript(key: String) -> Value? {
        entries.last { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    func string(_ key: String) -> String? {
        if case .string(let s) = self[key] { return s }
        return nil
    }

    func block(_ key: String) -> TextVDF? {
        if case .block(let b) = self[key] { return b }
        return nil
    }

    /// The block at a path of keys, matched the way Steam matches them (case-insensitively).
    func block(at path: [String]) -> TextVDF? {
        path.reduce(Optional(self)) { $0?.block($1) }
    }

    // MARK: - Editing

    /// Set a string, replacing an existing key in place or appending a new one.
    mutating func set(_ key: String, _ value: String) {
        set(key, .string(value))
    }

    mutating func set(_ key: String, _ value: Value) {
        if let i = entries.lastIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            entries[i].value = value
            entries[i].rawValue = nil          // Cellar's value now, so Cellar's escaping applies.
        } else {
            entries.append(Entry(key: key, value: value))
        }
    }

    /// Edit the block at `path`, creating any missing block along the way.
    mutating func edit(_ path: [String], _ change: (inout TextVDF) -> Void) {
        guard let first = path.first else { return change(&self) }
        var child = block(first) ?? TextVDF()
        child.edit(Array(path.dropFirst()), change)
        set(first, .block(child))
    }

    // MARK: - Writing

    /// Serialised with tabs, the way the client writes these files.
    var text: String {
        var out = ""
        write(into: &out, depth: 0)
        return out
    }

    private func write(into out: inout String, depth: Int) {
        let indent = String(repeating: "\t", count: depth)
        for entry in entries {
            let key = entry.key
            switch entry.value {
            case .string(let s):
                out += "\(indent)\"\(Self.escape(key))\"\t\t\"\(entry.rawValue ?? Self.escape(s))\"\n"
            case .block(let b):
                out += "\(indent)\"\(Self.escape(key))\"\n\(indent){\n"
                b.write(into: &out, depth: depth + 1)
                out += "\(indent)}\n"
            }
        }
    }

    /// Valve's four escapes, in both directions. All four matter for a round-trip: decoding `\n` and
    /// re-encoding it as a raw newline would rewrite a value Cellar never touched (`config.vdf` is
    /// rewritten whole), and decoding only `\\` would turn `\n` into `\\n`.
    private static func escape(_ s: String) -> String {
        var out = ""
        for c in s.unicodeScalars {
            switch c {
            case "\\":  out += "\\\\"
            case "\"":  out += "\\\""
            case "\n":  out += "\\n"
            case "\t":  out += "\\t"
            default:    out.unicodeScalars.append(c)
            }
        }
        return out
    }

    static func unescaped(_ c: Unicode.Scalar) -> Unicode.Scalar? {
        switch c {
        case "\\", "\"": return c
        case "n":        return "\n"
        case "t":        return "\t"
        default:         return nil
        }
    }

    private struct Scanner {
        let chars: [Unicode.Scalar]
        var i = 0

        init(_ chars: [Unicode.Scalar]) { self.chars = chars }

        var atEnd: Bool {
            mutating get { skipSpace(); return i >= chars.count }
        }

        mutating func skipSpace() {
            while i < chars.count {
                if chars[i].properties.isWhitespace {
                    i += 1
                } else if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                } else {
                    return
                }
            }
        }

        mutating func quoted() -> String? {
            skipSpace()
            guard i < chars.count, chars[i] == "\"" else { return nil }
            i += 1
            var s = String.UnicodeScalarView()
            while i < chars.count {
                let c = chars[i]; i += 1
                if c == "\"" { return String(s) }
                if c == "\\", i < chars.count, let decoded = TextVDF.unescaped(chars[i]) {
                    // Exactly the escapes `escape` writes, so reading and rewriting a file cannot
                    // change a value it did not touch.
                    s.append(decoded); i += 1
                } else {
                    s.append(c)
                }
            }
            return nil
        }

        /// A sequence of entries, up to a `}` when `closed`, or to the end of the file otherwise.
        mutating func block(closed: Bool) -> TextVDF? {
            var result = TextVDF()
            while true {
                skipSpace()
                if i >= chars.count { return closed ? nil : result }
                if chars[i] == "}" {
                    guard closed else { return nil }
                    i += 1
                    return result
                }
                guard let key = quoted() else { return nil }
                skipSpace()
                guard i < chars.count else { return nil }
                if chars[i] == "{" {
                    i += 1
                    guard let child = block(closed: true) else { return nil }
                    result.entries.append(Entry(key: key, value: .block(child)))
                } else {
                    let opening = i                     // the opening quote
                    guard let value = quoted() else { return nil }
                    // `i` is now past the closing quote: what lies between them is the value as
                    // written.
                    let raw = String(String.UnicodeScalarView(chars[(opening + 1)..<(i - 1)]))
                    result.entries.append(Entry(key: key, value: .string(value), rawValue: raw))
                }
            }
        }
    }
}
