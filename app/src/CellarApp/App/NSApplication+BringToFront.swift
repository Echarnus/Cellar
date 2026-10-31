import CellarDomain
import AppKit
import CellarData
import SwiftUI

extension NSApplication {
    /// Brings Cellar forward. Activation is cooperative from macOS 14, so the plain `activate()` is
    /// the call — `activate(ignoringOtherApps:)` is deprecated and its flag ignored.
    func bringToFront() {
        activate()
    }
}
