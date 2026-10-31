import CellarDomain
import Foundation

/// One owned GOG game, as much of it as Cellar needs to show a row and install it.
public struct GOGProduct: Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let slug: String
    /// Portrait / landscape art GOG publishes for the product, if any.
    public let portraitURL: String?
    public let heroURL: String?
    /// Whether GOG offers a Windows installer for it — a Linux-or-Mac-only title can't run here, and
    /// saying so up front beats a download that ends in "no exe found".
    public let hasWindowsInstaller: Bool
}
