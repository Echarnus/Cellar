import SwiftUI

/// Cellar's own mark: the keg from the app icon, drawn in code.
///
/// SF Symbols has a wine glass but no keg, and Cellar's rule for marks is to draw them, never to
/// bundle a picture (`StoreMark` follows the same rule for the storefronts). The geometry is the
/// icon's — bulged sides, elliptical rims seen from slightly above, two hoops, a tap at the front —
/// so the keg beside "Cellar" in the sidebar is recognisably the keg in the Dock.
///
/// Two styles cover every place the app uses it. `.filled` reads like a symbol glyph beside text
/// (the sidebar header, the welcome screen): a solid silhouette with the hoops cut out, which is
/// what keeps it a keg and not a pill at 14pt. `.outline` is the large, thin drawing on the empty
/// detail pane, where there is room for the lid and the hoops as lines.
public struct KegMark: View {
    public enum Style { case filled, outline }

    var size: CGFloat
    var style: Style

    public init(size: CGFloat = 16, style: Style = .filled) {
        self.size = size
        self.style = style
    }

    public var body: some View {
        Group {
            switch style {
            case .filled:
                KegShape.Filled().fill()
            case .outline:
                ZStack {
                    KegShape.Outline()
                        .stroke(style: StrokeStyle(lineWidth: max(1, size * 0.03), lineCap: .round, lineJoin: .round))
                    KegShape.Tap().fill()
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
