import CellarDomain
import SwiftUI
import CellarData
import CellarUI

/// Steam's QR challenge, drawn at a size a phone camera can actually read.
///
/// The modules come from `SteamQRCodeReader`, which reads back the code DepotDownloader draws in the
/// terminal. Rendered with `Canvas` — no library, no network, and crisp at any size because it is
/// rectangles rather than a scaled bitmap.
struct QRCodePanel: View {
    let modules: [[Bool]]

    /// Four modules of white margin, as the QR spec requires for reliable scanning.
    private let quietZone = 4

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Canvas { context, size in
                let count = modules.count + quietZone * 2
                guard count > 0 else { return }
                let module = min(size.width, size.height) / CGFloat(count)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                for (row, line) in modules.enumerated() {
                    for (column, dark) in line.enumerated() where dark {
                        let rect = CGRect(
                            x: CGFloat(column + quietZone) * module,
                            y: CGFloat(row + quietZone) * module,
                            // A hair of overlap, so seams between modules never show as light lines.
                            width: module + 0.5, height: module + 0.5)
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
            }
            .frame(width: 164, height: 164)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Steam sign-in QR code")
            VStack(alignment: .leading, spacing: 6) {
                Text("Scan with the Steam mobile app").font(.headline)
                Text("Open Steam on your phone, tap the menu, then Scan QR code. Cellar never sees your password.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The code refreshes every few seconds — that's Steam, not a problem.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.leading, 34)
    }
}
