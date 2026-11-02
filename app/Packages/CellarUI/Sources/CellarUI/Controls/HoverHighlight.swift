import SwiftUI

/// How a control answers the pointer resting on it.
///
/// Every button in Cellar reacts to hover, so a player can tell what is clickable before clicking
/// (Kenneth: "no hover effects on all buttons"). Two shapes, both quiet enough not to compete with
/// the selection: a bordered button brightens a touch, the way a toolbar button does; an icon or
/// text button grows a soft rounded backdrop, the way Finder's sidebar and toolbar items do.
/// A disabled control does not react: hovering something that won't do anything would be a lie.
public enum HoverHighlight {
    public enum Kind: Sendable { case lift, backdrop }

    /// The brightness change for `.lift`. Darkened in light mode, lightened in dark mode, so the
    /// change reads in both; stronger under Increase Contrast.
    public static func brightness(hovering: Bool, enabled: Bool, dark: Bool, increasedContrast: Bool = false) -> Double {
        guard hovering, enabled else { return 0 }
        let amount = increasedContrast ? 0.14 : 0.07
        return dark ? amount : -amount
    }

    /// The backdrop's opacity for `.backdrop`.
    public static func backdropOpacity(hovering: Bool, enabled: Bool, increasedContrast: Bool = false) -> Double {
        guard hovering, enabled else { return 0 }
        return increasedContrast ? 0.16 : 0.08
    }

    struct Modifier: ViewModifier {
        let kind: Kind
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            let increased = contrast == .increased
            Group {
                switch kind {
                case .lift:
                    content.brightness(HoverHighlight.brightness(hovering: hovering, enabled: enabled,
                                                                 dark: scheme == .dark, increasedContrast: increased))
                case .backdrop:
                    // The backdrop reaches a little past the control instead of padding it, so a
                    // control's layout is the same with or without the pointer on it.
                    content.background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(HoverHighlight.backdropOpacity(
                                hovering: hovering, enabled: enabled, increasedContrast: increased)))
                            .padding(.horizontal, -5).padding(.vertical, -3))
                }
            }
            .onHover { inside in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovering = inside }
            }
        }
    }
}

public extension View {
    /// Answers the pointer resting on this control; see `HoverHighlight`.
    func hoverHighlight(_ kind: HoverHighlight.Kind = .lift) -> some View {
        modifier(HoverHighlight.Modifier(kind: kind))
    }
}
