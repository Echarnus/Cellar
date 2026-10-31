import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

extension GameSummary {
    /// One word for where this game stands, shared by the pill and by VoiceOver.
    var statusText: String {
        switch nextStep {
        case .setup:   return String(localized: "Needs repair")
        case .install: return String(localized: "Not installed")
        case .play:    return String(localized: "Installed")
        }
    }

    var statusSymbol: String {
        switch nextStep {
        case .setup:   return "wrench.and.screwdriver"
        case .install: return "arrow.down.circle"
        case .play:    return "checkmark.circle.fill"
        }
    }

    var statusTint: Color {
        switch nextStep {
        case .setup:   return .orange
        case .install: return .secondary
        case .play:    return .green
        }
    }
}
