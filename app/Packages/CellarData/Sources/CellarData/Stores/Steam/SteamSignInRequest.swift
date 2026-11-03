import Foundation

/// A Steam Guard code the sign-in needs from the player.
///
/// The `cellar` CLI prints `sentence` and then reads the answer from stdin; the app recognises the
/// sentence with `init(sentence:)` and shows its own, translated, words beside a code box. The
/// sentences are the wire between the two, so they are written once, here.
public enum SteamSignInRequest: Equatable, Sendable {
    case emailCode(hint: String?, retry: Bool)
    case authenticatorCode(retry: Bool)

    public var isRetry: Bool {
        switch self {
        case .emailCode(_, let retry), .authenticatorCode(let retry): return retry
        }
    }

    static let emailLead = "Steam emailed you a sign-in code"
    static let authenticatorLead = "Enter the code shown in the Steam app on your phone"
    static let retryLead = "That code didn't work. "

    /// The CLI's line for this request. Plain words, ending in a colon: it is a question.
    public var sentence: String {
        let retry = isRetry ? Self.retryLead : ""
        switch self {
        case .emailCode(let hint, _):
            let address = hint.map { " (\($0))" } ?? ""
            return retry + Self.emailLead + address + ". Enter it:"
        case .authenticatorCode:
            return retry + Self.authenticatorLead + " (Steam Guard):"
        }
    }

    /// The request a CLI line asks, or nil when the line is not one.
    public init?(sentence line: String) {
        var text = line.trimmingCharacters(in: .whitespaces)
        let retry = text.hasPrefix(Self.retryLead)
        if retry { text.removeFirst(Self.retryLead.count) }
        if text.hasPrefix(Self.authenticatorLead) {
            self = .authenticatorCode(retry: retry)
        } else if text.hasPrefix(Self.emailLead) {
            var hint: String?
            if let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
                let inside = String(text[text.index(after: open)..<close])
                hint = inside.isEmpty ? nil : inside
            }
            self = .emailCode(hint: hint, retry: retry)
        } else {
            return nil
        }
    }
}
