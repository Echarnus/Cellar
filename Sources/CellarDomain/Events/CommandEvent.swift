import Foundation

/// What the CLI tells the app about a running command, besides the sentences the player reads.
///
/// `cellar install|launch|update --events` prints each of these as one JSON line,
/// `{"phase":"downloading","fraction":0.25,"type":"progress","v":1}`, and the app lifts those lines
/// out of the output before showing the rest. Versioned, so the CLI can say something new without an
/// older app reading it as a sentence, and a newer field can be added without breaking the old app.
///
/// The `::cellar-progress::` / `::cellar-stage::` markers (`InstallMarker`, `LaunchMarker`) are the
/// older form of the same thing. `--machine-progress` still prints them and `parse` still reads
/// them, so an app and a CLI from either side of this change keep understanding each other.
public enum CommandEvent: Equatable, Sendable {
    /// Where an install, an update or a launch's own update has got to.
    case install(InstallProgress)
    /// Where a launch has got to.
    case stage(LaunchStage)

    /// The wire version this build writes, and the newest it reads.
    public static let version = 1

    /// The event a use case reported, if it is one the app follows (sentences are printed as prose).
    public init?(_ event: GameEvent) {
        switch event {
        case .install(let progress): self = .install(progress)
        case .launch(let stage): self = .stage(stage)
        case .step: return nil
        }
    }

    // MARK: - Writing

    /// The JSON line for this event — one line, no trailing newline.
    public var line: String {
        let wire: Wire
        switch self {
        case .install(let progress):
            wire = Wire(v: Self.version, type: "progress", phase: progress.phase.rawValue,
                        fraction: progress.fraction, stage: nil)
        case .stage(let stage):
            wire = Wire(v: Self.version, type: "stage", phase: nil, fraction: nil, stage: stage.rawValue)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(wire), let text = String(data: data, encoding: .utf8) else {
            return ""   // unreachable: every field is a string or a number
        }
        return text
    }

    // MARK: - Reading

    /// The event a line carries — the JSON form or the older marker form — or nil when the line is
    /// something for the player to read.
    public static func parse(_ line: String) -> CommandEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let progress = InstallMarker.progress(in: trimmed) { return .install(progress) }
        if let stage = LaunchMarker.stage(in: trimmed) { return .stage(stage) }
        guard let wire = wire(in: trimmed), wire.v <= version else { return nil }
        switch wire.type {
        case "progress":
            guard let phase = wire.phase.flatMap(InstallPhase.init(rawValue:)) else { return nil }
            return .install(InstallProgress(phase, fraction: wire.fraction))
        case "stage":
            return wire.stage.flatMap(LaunchStage.init(rawValue:)).map(CommandEvent.stage)
        default:
            return nil
        }
    }

    /// Whether a line is an event at all — including one from a newer CLI this app can't read yet,
    /// which is hidden rather than shown to the player as a line of JSON.
    public static func isEvent(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return LaunchMarker.isMarker(trimmed) || trimmed.hasPrefix(InstallMarker.prefix) || wire(in: trimmed) != nil
    }

    private static func wire(in line: String) -> Wire? {
        // Every event is a JSON object; no sentence the CLI prints starts with `{"`.
        guard line.hasPrefix("{\""), let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Wire.self, from: data)
    }

    /// The JSON shape. `v` and `type` are always there; the rest depends on `type`, and a field this
    /// version doesn't know is ignored rather than refused.
    private struct Wire: Codable {
        let v: Int
        let type: String
        let phase: String?
        let fraction: Double?
        let stage: String?
    }
}
