import CellarDomain
import SwiftUI
import AppKit
import GameController
import CellarData
import CellarUI

/// How far a profile has actually been verified. Said plainly, because "untested" is information
/// the player needs *before* a two-hour download, not after it.
struct StatusBadge: View {
    let status: String

    private var tint: Color {
        switch status.lowercased() {
        case let s where s.hasPrefix("playable"): return .green
        case let s where s.hasPrefix("broken"), let s where s.hasPrefix("unplayable"): return .red
        default: return .orange
        }
    }

    var body: some View {
        Text(status.replacingOccurrences(of: "-", with: " "))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .accessibilityLabel("Compatibility status: \(status)")
    }
}
