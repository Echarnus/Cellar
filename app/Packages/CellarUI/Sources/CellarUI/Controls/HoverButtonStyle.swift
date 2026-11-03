import SwiftUI

/// The system's own button styles, each with Cellar's hover answer added. Set at each window's root
/// (`.buttonStyle(.hoverAutomatic)`) so a button that names no style gets it too, and used in place
/// of `.bordered`, `.borderedProminent`, `.borderless` and `.link` everywhere else.
public struct HoverButtonStyle: PrimitiveButtonStyle {
    public enum Base: Sendable { case automatic, bordered, borderedProminent, borderless, link }
    public let base: Base

    public init(_ base: Base) { self.base = base }

    /// Which hover answer a base style gets: a bordered button has a shape to brighten; a
    /// borderless or link button has none, so it is given one.
    public static func kind(for base: Base) -> HoverHighlight.Kind {
        switch base {
        case .automatic, .bordered, .borderedProminent: return .lift
        case .borderless, .link: return .backdrop
        }
    }

    @ViewBuilder public func makeBody(configuration: Configuration) -> some View {
        let kind = Self.kind(for: base)
        switch base {
        case .automatic:         Button(configuration).buttonStyle(.automatic).hoverHighlight(kind)
        case .bordered:          Button(configuration).buttonStyle(.bordered).hoverHighlight(kind)
        case .borderedProminent: Button(configuration).buttonStyle(.borderedProminent).hoverHighlight(kind)
        case .borderless:        Button(configuration).buttonStyle(.borderless).hoverHighlight(kind)
        case .link:              Button(configuration).buttonStyle(.link).hoverHighlight(kind)
        }
    }
}

public extension PrimitiveButtonStyle where Self == HoverButtonStyle {
    static var hoverAutomatic: HoverButtonStyle { HoverButtonStyle(.automatic) }
    static var hoverBordered: HoverButtonStyle { HoverButtonStyle(.bordered) }
    static var hoverProminent: HoverButtonStyle { HoverButtonStyle(.borderedProminent) }
    static var hoverBorderless: HoverButtonStyle { HoverButtonStyle(.borderless) }
    static var hoverLink: HoverButtonStyle { HoverButtonStyle(.link) }
}
