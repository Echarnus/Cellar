import CellarDomain
import SwiftUI
import AppKit
import GameController
import CellarData
import CellarUI

struct Chip: View {
    let text: String
    let system: String
    var tint: Color = .secondary

    init(_ text: String, system: String, tint: Color = .secondary) {
        self.text = text
        self.system = system
        self.tint = tint
    }

    var body: some View {
        Label(text, systemImage: system).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
    }
}
