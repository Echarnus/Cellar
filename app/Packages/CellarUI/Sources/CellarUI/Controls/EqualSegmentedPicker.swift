import AppKit
import SwiftUI

/// A segmented control whose segments are all the same width, whichever is selected.
///
/// SwiftUI's `.segmented` picker sizes each segment to its label on macOS, so "All" is a sliver
/// beside "Not installed" and the control seems to shift as the selection moves. AppKit's own
/// control can share the width out evenly (`segmentDistribution = .fillEqually`), which is how
/// Finder's and Mail's toolbars look. It is still the system's control: same look, same keyboard
/// and VoiceOver behaviour, and it follows light, dark and Increase Contrast by itself.
public struct EqualSegmentedPicker: NSViewRepresentable {
    let labels: [String]
    @Binding var selection: Int
    let accessibilityLabel: String

    public init(_ labels: [String], selection: Binding<Int>, accessibilityLabel: String) {
        self.labels = labels
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
    }

    /// The control itself, configured. Static so a test can build one and measure its segments.
    public static func makeControl(labels: [String], selected: Int) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .automatic
        control.selectedSegment = selected
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    public func makeNSView(context: Context) -> NSSegmentedControl {
        let control = Self.makeControl(labels: labels, selected: selection)
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setAccessibilityLabel(accessibilityLabel)
        return control
    }

    public func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.selectedSegment != selection { control.selectedSegment = selection }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor
    public final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) { selection.wrappedValue = sender.selectedSegment }
    }
}
