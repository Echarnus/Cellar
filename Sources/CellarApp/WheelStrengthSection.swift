import SwiftUI
import CellarKit

/// Settings › General › Racing wheels: how hard a wheel Cellar drives may push. Kept in
/// `settings.toml` and handed to Cellar's SDL at launch (`CellarSDL.strengthEnvironment`).
///
/// Writes through CellarKit directly rather than through the `cellar` subprocess, for the same
/// reason as `GameLanguageSection`: one line in a settings file, which must not be refused while a
/// game is playing.
struct WheelStrengthSection: View {
    /// nil = Cellar's default. Loaded after the first layout, never from the body (skills/swift.md).
    @State private var chosen: Int?
    @State private var failure: String?

    var body: some View {
        Section("Racing wheels") {
            Picker("Force feedback strength", selection: Binding(get: { chosen }, set: save)) {
                Text("Cellar's default").tag(Int?.none)
                Divider()
                ForEach(CellarSDL.strengthChoices, id: \.self) { percent in
                    Text("\(percent)%").tag(Int?.some(percent))
                }
            }
            Text(note)
                .font(.caption).foregroundStyle(.secondary)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .task { chosen = CellarSettings.forceFeedbackStrength }
    }

    /// What the choice means, then the one thing worth knowing before raising it.
    private var note: String {
        let what = chosen.map { "Every wheel Cellar drives pushes at most \($0)% of its maximum." }
            ?? "Fanatec bases start at half strength and Logitech wheels at full."
        return what + " Applies from a game's next launch. A direct-drive base is strong: raise it a step at a time. The base's own force-feedback setting still applies on top."
    }

    private func save(_ percent: Int?) {
        do {
            try CellarSettings.setForceFeedbackStrength(percent)
            chosen = percent
            failure = nil
        } catch {
            failure = "Couldn't save the strength: \(CellarLog.describe(error))"
        }
    }
}
