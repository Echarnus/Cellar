import Testing
import SwiftUI
import Foundation
import CellarKit
import CellarUI

/// Renders every store mark, lockup and cover into one PNG.
///
/// The measurements in `StoreMarkTests` catch the mistakes somebody thought to describe. This
/// catches the rest, by putting the whole set in front of a human in one glance — light and dark,
/// every size, side by side — without installing the app and launching it. It is the "look at it"
/// half of the verification ladder, made cheap enough to do on every change.
///
/// It always passes; its output is the point. The sheet lands in `.build/ui-snapshots/`, and the
/// path is printed so it can be opened straight from the test log.
@MainActor
@Suite("Contact sheet")
struct ContactSheetTests {

    static var outputDirectory: URL {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/ui-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("draw every mark, light and dark, at every size it is used")
    func drawContactSheet() throws {
        for scheme in [ColorScheme.light, .dark] {
            let sheet = ContactSheet().environment(\.colorScheme, scheme)
            let bitmap = Snapshot.render(sheet,
                                         size: CGSize(width: 620, height: 380),
                                         scale: 2,
                                         background: scheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
            let data = try #require(bitmap.pngData(), "the contact sheet rendered no PNG data")
            let url = Self.outputDirectory.appendingPathComponent("store-marks-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: url)
            print("contact sheet → \(url.path)")
        }
    }
}

/// Every mark the app draws, in the sizes it draws them at, with its name underneath.
private struct ContactSheet: View {
    private let sizes: [CGFloat] = [11, 14, 22, 32, 48]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cellar store marks")
                .font(.headline)

            ForEach(GameStore.allCases, id: \.self) { store in
                HStack(alignment: .center, spacing: 18) {
                    Text(store.displayName)
                        .font(.caption.weight(.semibold))
                        .frame(width: 78, alignment: .leading)

                    ForEach(sizes, id: \.self) { size in
                        VStack(spacing: 4) {
                            StoreMark(store: store, size: size, artwork: false)
                                .frame(width: 48, height: 48)
                            Text("\(Int(size))")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }

                    StoreLockup(store: store)
                    StoreBadge(store: store, diameter: 20)
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 380, alignment: .topLeading)
    }
}
