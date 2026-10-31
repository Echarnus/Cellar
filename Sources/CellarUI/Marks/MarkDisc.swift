import CellarDomain
import SwiftUI
import AppKit
import CellarKit

/// A disc whose centre and radius are fractions of the mark's box.
nonisolated struct MarkDisc: Shape {
    let center: CGPoint, radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let r = radius * s
        return Path(ellipseIn: CGRect(x: rect.minX + center.x * s - r,
                                      y: rect.minY + center.y * s - r,
                                      width: r * 2, height: r * 2))
    }
}
