import CellarDomain
import SwiftUI

/// How likely the game is to work, on the game page — before a two-hour download, not after.
///
/// A tested game says what the test found. Every other game says Cellar's estimate *and* that it
/// is one: the badge always carries "Not tested" for an estimate, so a guess never reads as a
/// result (`docs/COMPATIBILITY.md`). The reasons are in Technical Details.
struct ForecastBadge: View {
    let forecast: CompatibilityForecast

    static func tint(_ outlook: CompatibilityForecast.Outlook) -> Color {
        switch outlook {
        case .works: return .green
        case .likely: return .teal
        case .unsure: return .orange
        case .unlikely, .wontWork: return .red
        }
    }

    private var label: String {
        forecast.basis == .tested ? forecast.title
            : String(localized: "\(forecast.title) · Not tested")
    }

    var body: some View {
        let tint = Self.tint(forecast.outlook)
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .help(forecast.detail)
            .accessibilityLabel(String(localized: "Compatibility: \(label). \(forecast.detail)"))
    }
}
