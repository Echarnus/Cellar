import CellarDomain
import SwiftUI
import AppKit
import CellarKit

/// A straight segment between two points given in fractions of the mark's box.
nonisolated struct MarkLine: Shape {
    let from: CGPoint, to: CGPoint

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + from.x * s, y: rect.minY + from.y * s))
        path.addLine(to: CGPoint(x: rect.minX + to.x * s, y: rect.minY + to.y * s))
        return path
    }
}
