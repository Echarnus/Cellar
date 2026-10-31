import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            KegMark(size: 64, style: .outline).foregroundStyle(.pink.gradient)
            Text("Choose a game").font(.title2.weight(.semibold))
            Text("Windows games, running on your Mac.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
