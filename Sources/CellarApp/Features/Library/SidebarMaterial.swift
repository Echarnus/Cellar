import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

/// The sidebar's translucent material. `NSVisualEffectView` rather than a SwiftUI `Material`,
/// because only AppKit's `.sidebar` material is the exact one Finder and Mail use — and it adapts
/// to Reduce Transparency on its own.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
