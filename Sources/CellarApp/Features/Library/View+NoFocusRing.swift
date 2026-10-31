import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

extension View {
    /// A list the keyboard can reach shouldn't draw a blue ring round the whole sidebar: the
    /// selected row is the focus indicator, as in Finder.
    func noFocusRing() -> some View {
        focusEffectDisabled()
    }
}
