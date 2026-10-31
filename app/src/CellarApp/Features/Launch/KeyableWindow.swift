import CellarDomain
import AppKit
import SwiftUI
import CellarData
import CellarUI

/// A borderless window that can still take the keyboard — AppKit refuses that by default, and
/// without it the launch window's buttons could not be reached by Tab or Escape.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
