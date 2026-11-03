import SwiftUI
import AppKit
import Testing
@testable import CellarUI

/// Every button answers the pointer (Kenneth, "no hover effects on all buttons"). Hover can't be
/// simulated offscreen, so these hold the rules the modifier draws from.
@MainActor
@Suite("Hover highlight")
struct HoverHighlightTests {
    @Test("Hovering changes the control in both themes, and in the direction that reads in each")
    func liftsInBothThemes() {
        #expect(HoverHighlight.brightness(hovering: true, enabled: true, dark: true) > 0)
        #expect(HoverHighlight.brightness(hovering: true, enabled: true, dark: false) < 0)
        #expect(HoverHighlight.backdropOpacity(hovering: true, enabled: true) > 0)
    }

    @Test("Nothing changes without the pointer, or on a disabled control")
    func quietOtherwise() {
        for dark in [true, false] {
            #expect(HoverHighlight.brightness(hovering: false, enabled: true, dark: dark) == 0)
            #expect(HoverHighlight.brightness(hovering: true, enabled: false, dark: dark) == 0)
        }
        #expect(HoverHighlight.backdropOpacity(hovering: false, enabled: true) == 0)
        #expect(HoverHighlight.backdropOpacity(hovering: true, enabled: false) == 0)
    }

    @Test("Increase Contrast makes the answer stronger")
    func contrast() {
        #expect(abs(HoverHighlight.brightness(hovering: true, enabled: true, dark: true, increasedContrast: true))
                > abs(HoverHighlight.brightness(hovering: true, enabled: true, dark: true)))
        #expect(HoverHighlight.backdropOpacity(hovering: true, enabled: true, increasedContrast: true)
                > HoverHighlight.backdropOpacity(hovering: true, enabled: true))
    }

    @Test("A button with no border of its own gets a backdrop; a bordered one brightens")
    func kinds() {
        #expect(HoverButtonStyle.kind(for: .borderless) == .backdrop)
        #expect(HoverButtonStyle.kind(for: .link) == .backdrop)
        #expect(HoverButtonStyle.kind(for: .bordered) == .lift)
        #expect(HoverButtonStyle.kind(for: .borderedProminent) == .lift)
        #expect(HoverButtonStyle.kind(for: .automatic) == .lift)
    }

    @Test("Every hover style draws its button, the way the system style would")
    func everyStyleDraws() {
        let sheet = VStack(spacing: 8) {
            Button("Automatic") {}.buttonStyle(.hoverAutomatic)
            Button("Bordered") {}.buttonStyle(.hoverBordered)
            Button("Prominent") {}.buttonStyle(.hoverProminent)
            Button("Borderless") {}.buttonStyle(.hoverBorderless)
            Button("Link") {}.buttonStyle(.hoverLink)
            Button("Disabled") {}.buttonStyle(.hoverBordered).disabled(true)
            Text("Menu").hoverHighlight(.backdrop)
        }
        .padding()
        let host = NSHostingView(rootView: sheet)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 320)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 100, "the buttons took no room")
    }
}
