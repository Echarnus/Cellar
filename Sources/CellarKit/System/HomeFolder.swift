import CellarDomain
import Foundation

/// The macOS folders a Windows game reaches into, and the one-time permission grant they need.
///
/// `wineboot --init` builds a Windows user profile whose *My Documents*, *Desktop* and *Downloads*
/// are symlinks to the real `~/Documents`, `~/Desktop` and `~/Downloads` — which is what a player
/// wants (a Skyrim save lands in `Documents/My Games`, where a Mac backup will pick it up). Those
/// three are exactly the folders macOS protects, so the first game that reads or writes a save puts
/// up *"Cellar.app would like to access files in your Documents folder"* — in the middle of an
/// install, with nothing on screen explaining why.
///
/// So Cellar asks for all three at once, on first launch, having said what they are for. macOS
/// remembers the answer, and a "Don't Allow" is honoured rather than fought: a denied folder is
/// re-pointed inside the bottle (`redirectDeniedUserShellFolders`) so the game keeps its saves
/// somewhere writable instead of silently failing to write them.
public enum HomeFolder: String, CaseIterable, Sendable {
    case documents, desktop, downloads

    public var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(displayName, isDirectory: true)
    }

    /// The folder's name as macOS shows it in the permission dialog and in System Settings — and,
    /// as it happens, the name Wine gives it inside the Windows user profile.
    public var displayName: String {
        switch self {
        case .documents: return "Documents"
        case .desktop:   return "Desktop"
        case .downloads: return "Downloads"
        }
    }

    /// One sentence a player can act on — why a Windows game wants this folder.
    public var reason: String {
        switch self {
        case .documents: return "Most Windows games keep saves and settings here, under My Games."
        case .desktop:   return "Installers put shortcuts here, and some games save screenshots to it."
        case .downloads: return "Game installers and patches you download land here."
        }
    }

    public var symbolName: String {
        switch self {
        case .documents: return "doc.text"
        case .desktop:   return "menubar.dock.rectangle"
        case .downloads: return "arrow.down.circle"
        }
    }
}
