import CellarDomain
import SwiftUI
import AppKit
import CellarKit

// MARK: - Pieces

/// A page's title and its one plain sentence saying what this step is for.
struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40).padding(.top, 30).padding(.bottom, 20)
    }
}
