import Foundation

/// Where the library comes from: the port the app's library asks, so a view model never reads the
/// disk itself. The engine implements it (`DiskLibraryRepository`); a test or a preview hands in a
/// fixed snapshot instead.
public protocol LibraryRepository: Sendable {
    /// The library as it stands now. Never asks a store anything over the network: it runs on
    /// every refresh.
    func snapshot() -> LibrarySnapshot
}
