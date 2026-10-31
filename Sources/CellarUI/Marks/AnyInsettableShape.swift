import CellarDomain
import SwiftUI
import AppKit
import CellarKit

/// A type-erased `InsettableShape`, so `outline(of:size:)` can hand back either a circle or a tile
/// and callers can still `strokeBorder` it. SwiftUI's own `AnyShape` loses insettability.
nonisolated public struct AnyInsettableShape: InsettableShape {
    private let makePath: @Sendable (CGRect) -> Path
    private let makeInset: @Sendable (CGFloat) -> AnyInsettableShape

    public init<S: InsettableShape & Sendable>(_ shape: S) {
        makePath = { shape.path(in: $0) }
        makeInset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    public func path(in rect: CGRect) -> Path { makePath(rect) }
    public func inset(by amount: CGFloat) -> AnyInsettableShape { makeInset(amount) }
}
