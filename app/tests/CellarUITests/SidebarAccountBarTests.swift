import CellarDomain
import Testing
import SwiftUI
import Foundation
@testable import CellarUI

/// The account bar at the foot of the sidebar, drawn offscreen in each state it can be in.
///
/// The sheet lands in `.build/ui-snapshots/sidebar-account-bar-{light,dark}.png`. The measurements
/// check the one thing a player reads before the words: the avatar says *signed out* in the accent
/// colour, *signed in* in quiet grey, and *needs you* with an orange badge.
@MainActor
@Suite("Sidebar account bar")
struct SidebarAccountBarTests {

    static let signedOut = AccountSummary(connected: [], steam: .signedOut)
    static let connected = AccountSummary(connected: [.steam, .gog],
                                          steam: .signedIn(account: "kenneth", days: 3, aging: false))
    static let expired = AccountSummary(connected: [.gog], steam: .expired(account: "kenneth", reason: "revoked"))

    static let barSize = CGSize(width: 280, height: 52)

    private func render(_ account: AccountSummary, _ scheme: ColorScheme = .dark) -> Snapshot.Bitmap {
        Snapshot.render(SidebarAccountBar(account: account, openAccounts: {}, openSettings: {})
                            .environment(\.colorScheme, scheme),
                        size: Self.barSize, scale: 2,
                        background: scheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
    }

    /// The avatar's pixels only: the bar's leading 8pt padding, 6pt inset and 28pt avatar, plus the
    /// badge's 2pt overhang — at 2x.
    private func avatarPixels(_ bitmap: Snapshot.Bitmap) -> [Snapshot.Bitmap.Pixel] {
        var pixels: [Snapshot.Bitmap.Pixel] = []
        bitmap.forEachPixel { x, _, pixel in if x >= 12, x < 96 { pixels.append(pixel) } }
        return pixels
    }

    private static func isTinted(_ p: Snapshot.Bitmap.Pixel) -> Bool {
        max(p.r, p.g, p.b) - min(p.r, p.g, p.b) > 0.25
    }

    private static func isBlue(_ p: Snapshot.Bitmap.Pixel) -> Bool { p.b > 0.6 && p.b - p.r > 0.3 }
    private static func isOrange(_ p: Snapshot.Bitmap.Pixel) -> Bool { p.r > 0.7 && p.r - p.b > 0.4 && p.g > 0.3 }

    @Test("Signed out, the avatar is the accent-coloured invitation to sign in",
          arguments: [false, true])
    func signedOutIsAccent(dark: Bool) {
        let scheme: ColorScheme = dark ? .dark : .light
        let avatar = avatarPixels(render(Self.signedOut, scheme))
        #expect(avatar.filter(Self.isBlue).count > 40, "no accent-blue in the signed-out avatar")
        #expect(!avatar.contains(where: Self.isOrange))
    }

    @Test("Signed in, the avatar is quiet: no colour competes with the games above it",
          arguments: [false, true])
    func connectedIsQuiet(dark: Bool) {
        let scheme: ColorScheme = dark ? .dark : .light
        let avatar = avatarPixels(render(Self.connected, scheme))
        #expect(avatar.filter(Self.isTinted).count < 10, "the signed-in avatar is tinted")
        // It is still drawn: something other than the background is there.
        let background = scheme == .dark ? 0.13 : 0.97
        #expect(avatar.contains { abs($0.luminance - background) > 0.2 }, "the signed-in avatar drew nothing")
    }

    @Test("An expired Steam sign-in badges the avatar orange", arguments: [false, true])
    func expiredIsBadged(dark: Bool) {
        let scheme: ColorScheme = dark ? .dark : .light
        let avatar = avatarPixels(render(Self.expired, scheme))
        #expect(avatar.filter(Self.isOrange).count > 10, "no orange badge on an expired sign-in")
    }

    @Test("draw the account bar in every state, light and dark")
    func drawSheet() throws {
        for scheme in [ColorScheme.light, .dark] {
            let sheet = VStack(alignment: .leading, spacing: 0) {
                ForEach([("Signed out", Self.signedOut), ("Signed in", Self.connected),
                         ("Steam expired", Self.expired)], id: \.0) { label, account in
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.top, 10)
                    Divider()
                    SidebarAccountBar(account: account, openAccounts: {}, openSettings: {})
                }
            }
            .frame(width: Self.barSize.width, alignment: .leading)
            .environment(\.colorScheme, scheme)
            let bitmap = Snapshot.render(sheet, size: CGSize(width: Self.barSize.width, height: 240), scale: 2,
                                         background: scheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
            let data = try #require(bitmap.pngData(), "the account bar rendered no PNG data")
            let url = ContactSheetTests.outputDirectory
                .appendingPathComponent("sidebar-account-bar-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: url)
            print("account bar → \(url.path)")
        }
    }
}
