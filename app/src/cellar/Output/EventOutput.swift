import CellarDomain
import CellarData

/// Where a command's progress events go: nowhere (a person at a terminal), the versioned JSON lines
/// of `--events` (the app), or the older `::cellar-…::` markers of `--machine-progress` (an app from
/// before the JSON form, kept until no installed app needs it).
struct EventOutput {
    var json: Bool
    var markers: Bool

    var isOn: Bool { json || markers }

    func emit(_ event: CommandEvent) {
        if json { print(event.line) }
        if markers {
            switch event {
            case .install(let progress): print(InstallMarker.line(progress))
            case .stage(let stage): print(LaunchMarker.line(stage))
            }
        }
    }
}
