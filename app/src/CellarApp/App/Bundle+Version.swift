import CellarDomain
import AppKit
import CellarKit
import SwiftUI

extension Bundle {
    /// The version shown in About and written into the log; falls back to the library's own
    /// version when the app runs unwrapped during development.
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? CellarVersion.current
    }
}
