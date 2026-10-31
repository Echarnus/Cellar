import CellarDomain
import SwiftUI
import CellarData

/// Settings › General › Language: the language every game, and the store client that starts it,
/// runs in. Follows the Mac unless the player picks one; a game can still have its own (its •••
/// menu, `GameLanguageMenu`).
///
/// Writes through CellarData directly rather than through the `cellar` subprocess: it is one line in
/// a settings file, and the app's runner refuses work while a game is playing — a picker that
/// silently did nothing mid-game would be worse than one that bypasses it.
struct GameLanguageSection: View {
    /// nil = follow the Mac. Loaded after the first layout, never from the body (skills/swift.md).
    @State private var chosen: GameLanguage?
    @State private var failure: String?
    private let system = GameLanguage.system()

    var body: some View {
        Section("Language") {
            Picker("Games run in", selection: Binding(get: { chosen }, set: save)) {
                Text("Same as my Mac — \(system.nativeName)").tag(GameLanguage?.none)
                Divider()
                ForEach(GameLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName).tag(GameLanguage?.some(language))
                }
            }
            Text("Games and Steam start in this language from their next launch. A game that doesn't include it shows English. To give one game its own language, use the ••• menu on its page.")
                .font(.caption).foregroundStyle(.secondary)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .task { chosen = CellarSettings.language.flatMap(GameLanguage.named) }
    }

    private func save(_ language: GameLanguage?) {
        do {
            try CellarSettings.setLanguage(language)
            chosen = language
            failure = nil
        } catch {
            failure = "Couldn't save the language: \(CellarLog.describe(error))"
        }
    }
}
