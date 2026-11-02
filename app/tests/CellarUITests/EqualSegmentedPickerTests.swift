import AppKit
import Testing
@testable import CellarUI

/// The library's All / Installed / Not installed filter. Kenneth: the segments must not change size
/// when another one is selected. Measured on the real AppKit control, laid out at the sidebar's width.
@MainActor
@Suite("Equal-width segmented picker")
struct EqualSegmentedPickerTests {
    static let labels = ["All", "Installed", "Not installed"]

    private func widths(selected: Int, width: CGFloat = 220) -> [CGFloat] {
        let control = EqualSegmentedPicker.makeControl(labels: Self.labels, selected: selected)
        control.frame = NSRect(x: 0, y: 0, width: width, height: 24)
        control.layoutSubtreeIfNeeded()
        return (0..<control.segmentCount).map { control.width(forSegment: $0) == 0
            ? control.bounds.width / CGFloat(control.segmentCount)   // 0 means "automatic", i.e. shared
            : control.width(forSegment: $0) }
    }

    @Test("Shares the width out evenly")
    func fillsEqually() {
        let control = EqualSegmentedPicker.makeControl(labels: Self.labels, selected: 0)
        #expect(control.segmentDistribution == .fillEqually)
        #expect(control.segmentCount == 3)
        // No segment is given a fixed width of its own, which would override the even split.
        #expect((0..<3).allSatisfy { control.width(forSegment: $0) == 0 })
    }

    @Test("The segments keep their size whichever one is selected", arguments: [0, 1, 2])
    func stableAcrossSelection(selected: Int) {
        let measured = widths(selected: selected)
        #expect(measured == widths(selected: 0))
        #expect(Set(measured.map { $0.rounded() }).count == 1, "segments differ in width: \(measured)")
    }

    @Test("Selecting a segment in the control reaches the binding")
    func reportsSelection() {
        var value = 0
        let coordinator = EqualSegmentedPicker.Coordinator(selection: .init(get: { value }, set: { value = $0 }))
        let control = EqualSegmentedPicker.makeControl(labels: Self.labels, selected: 0)
        control.selectedSegment = 2
        coordinator.changed(control)
        #expect(value == 2)
    }
}
