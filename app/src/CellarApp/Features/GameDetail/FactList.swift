import CellarDomain
import SwiftUI
import AppKit
import GameController
import CellarData
import CellarUI

/// A titled label/value list. Values wrap; labels stay a fixed column so two lists line up.
struct FactList: View {
    let title: String
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .kerning(0.5).textCase(.uppercase)
            ForEach(rows, id: \.label) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.label).font(.callout).foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    Text(row.value).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}
