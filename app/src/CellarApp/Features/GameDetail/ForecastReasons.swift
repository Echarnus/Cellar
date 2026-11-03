import CellarDomain
import SwiftUI

/// Why Cellar expects what the badge says, for Technical Details: one line per fact, with where
/// Cellar learned it.
struct ForecastReasons: View {
    let forecast: CompatibilityForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("What Cellar expects").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .kerning(0.5).textCase(.uppercase)
                ForecastBadge(forecast: forecast)
            }
            Text(forecast.detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(forecast.reasons.enumerated()), id: \.offset) { _, reason in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Self.symbol(reason.effect))
                        .foregroundStyle(Self.color(reason.effect))
                        .accessibilityHidden(true)
                    Text(reason.source.map { "\(reason.text) (\($0))" } ?? reason.text)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let online = forecast.online {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "network").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(online).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static func symbol(_ effect: CompatibilityForecast.Reason.Effect) -> String {
        switch effect {
        case .helps: return "plus.circle.fill"
        case .hurts: return "minus.circle.fill"
        case .blocks: return "xmark.octagon.fill"
        case .note: return "info.circle"
        }
    }

    static func color(_ effect: CompatibilityForecast.Reason.Effect) -> Color {
        switch effect {
        case .helps: return .green
        case .hurts: return .orange
        case .blocks: return .red
        case .note: return .secondary
        }
    }
}
