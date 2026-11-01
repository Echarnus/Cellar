import CellarDomain
import Foundation

/// What a crash, or a connection that never made it through TLS, leaves behind (#203).
///
/// Every check here reads text a game run already produces: the process table, and the Wine log
/// the game's output goes to. So it costs nothing to run on every game, and it is the same for
/// every game: a profile only ever adds to it.
public enum CrashSigns {
    /// The crash reporters games and engines ship, plus Wine's own debugger, which Wine starts on
    /// an unhandled exception. Any of these appearing while a game runs means it crashed: the
    /// Frontier one is the window Kenneth kept seeing on Planet Coaster 2.
    static let reporterPattern =
        #"(?i)(crash_?reporter|crashsender\d*|crashreportclient|unitycrashhandler(32|64)?|bssndrpt(64)?|werfault|steamerrorreporter(64)?|crashpad_handler)\.exe|\bwinedbg\b"#

    /// The command lines in `ps -axo command` output that are a crash reporter. Chromium's own
    /// crash handler inside Steam's web helper is Steam's housekeeping, not a crash, so lines from
    /// `steamwebhelper` are left out.
    public static func crashReporters(inProcessList text: String, extra: [String] = []) -> [String] {
        let pattern = extra.isEmpty ? reporterPattern
            : reporterPattern + "|" + extra.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            !line.lowercased().contains("steamwebhelper")
                && regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    /// Lines in a Wine log that say a process crashed: an unhandled exception or page fault, an
    /// access violation, or Planet Coaster 2's own fatal 0xFDEAD.
    public static func crashLines(inWineLog text: String) -> [String] {
        matching(#"(?i)unhandled (exception|page fault)|\bc0000005\b|\b0x0*fdead\b|wine: .*(crashed|terminated)"#, text)
    }

    /// Lines in a Wine log where TLS or certificate handling failed: Schannel (`secur32`),
    /// certificate chains (`crypt`, `chain`) and the HTTP stacks above them. These are the errors
    /// a probe that passes can hide, because the game's own TLS goes through them and the probe's
    /// may not.
    public static func tlsErrors(inWineLog text: String) -> [String] {
        matching(#"err:(secur32|schannel|crypt|chain|winhttp|wininet|bcrypt|ncrypt)"#, text)
    }

    /// The Wine debug channels `cellar verify` turns on so the lines above are written at all:
    /// a game normally runs with `WINEDEBUG=-all`, which silences them.
    public static let wineDebugChannels = "err+seh,err+secur32,err+schannel,err+crypt,err+chain,err+winhttp,err+wininet,err+bcrypt,err+ncrypt"

    /// `WINEDEBUG` for a verified run: the game's own value, with the channels above added.
    public static func wineDebug(adding current: String?) -> String {
        guard let current, !current.isEmpty, current != "-all" else { return "-all," + wineDebugChannels }
        return current + "," + wineDebugChannels
    }

    private static func matching(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }
}
