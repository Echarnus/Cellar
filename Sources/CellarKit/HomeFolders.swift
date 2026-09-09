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

/// What this process may do with those folders, and the one-time ask.
///
/// Everything here reports on **the running process**: for `Cellar.app` that is the app, and every
/// `cellar`/wine subprocess it spawns inherits it as the responsible process, which is why the
/// dialog in the screenshot names Cellar.app. A `cellar` run from a terminal reports the terminal's
/// grant instead. Nothing else is knowable — macOS exposes no API for reading the privacy database
/// — so no surface may claim otherwise.
public enum HomeFolderAccess {
    public enum Access: String, Sendable {
        case granted    // the folder can be listed
        case denied     // macOS refused
    }

    /// Set once the first-run ask has run to completion, so it is never put in front of the player
    /// twice. macOS itself prompts only once per folder, whichever way it was answered.
    private static let askedKey = "homeFolderAccessRequested"

    public static var hasAsked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    /// Ask macOS for one folder. **This is the call that shows the system dialog** — the first time
    /// only; afterwards it returns the recorded answer immediately. It blocks until the player
    /// answers, so never run it on the main thread.
    ///
    /// There is no "check without asking": reading the directory *is* the request. Which is the
    /// whole reason Cellar decides when it happens, rather than leaving it to a game.
    @discardableResult
    public static func request(_ folder: HomeFolder) -> Access {
        // A folder that isn't there at all is not a permission problem, and calling it denied would
        // send the player to System Settings to fix nothing.
        guard FileManager.default.fileExists(atPath: folder.url.path) else { return .granted }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder.url.path)
            return .granted
        } catch let error as NSError {
            // Only a refusal counts as denied. Any other I/O failure is some other problem, and
            // reading it as "no" would redirect a bottle's save folder over, say, a transient
            // filesystem error.
            let refused = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
            return refused ? .denied : .granted
        }
    }

    /// Ask for every folder Cellar needs, one dialog after the other, reporting each answer as it
    /// lands so a UI can tick the rows off. Blocking — call it off the main thread.
    @discardableResult
    public static func requestAll(each: (HomeFolder, Access) -> Void = { _, _ in }) -> [HomeFolder: Access] {
        var result: [HomeFolder: Access] = [:]
        for folder in HomeFolder.allCases {
            let access = request(folder)
            result[folder] = access
            each(folder, access)
        }
        hasAsked = true
        return result
    }

    /// The current answer for every folder. Still blocking, and on a first run it still asks —
    /// there is no other way to find out.
    public static func statuses() -> [HomeFolder: Access] {
        var result: [HomeFolder: Access] = [:]
        for folder in HomeFolder.allCases { result[folder] = request(folder) }
        return result
    }

    /// System Settings → Privacy & Security → Files and Folders, where a decision is reversed.
    public static var systemSettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
    }

    // MARK: - Reconciling a bottle with the answer

    /// Point a bottle's Windows user folders at somewhere writable.
    ///
    /// Run right after `wineboot --init`. Wine has just symlinked *Documents*, *Desktop* and
    /// *Downloads* into the real home folder; for any folder macOS refuses, that symlink leads
    /// somewhere the game cannot read or write — and a game that cannot write a save usually says
    /// nothing, it just loses progress. Replacing the symlink with a real directory inside the
    /// bottle keeps the game working: the saves live in the bottle rather than in `~/Documents`,
    /// which is the honest consequence of "Don't Allow" and exactly what the first-run window says
    /// will happen.
    ///
    /// Returns the folders that were redirected, so the caller can say so.
    @discardableResult
    public static func redirectDeniedUserShellFolders(in prefix: URL) -> [HomeFolder] {
        let fm = FileManager.default
        let usersDir = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let profiles = try? fm.contentsOfDirectory(atPath: usersDir.path) else { return [] }

        var redirected: [HomeFolder] = []
        for folder in HomeFolder.allCases where request(folder) == .denied {
            for profile in profiles where profile != "Public" {
                let link = usersDir.appendingPathComponent(profile, isDirectory: true)
                    .appendingPathComponent(folder.displayName)
                // Only ever replace Wine's own symlink. A real directory is either already
                // redirected or holds a game's saves, and must not be touched.
                guard let attrs = try? fm.attributesOfItem(atPath: link.path),
                      attrs[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
                try? fm.removeItem(at: link)
                try? fm.createDirectory(at: link, withIntermediateDirectories: true)
                if !redirected.contains(folder) { redirected.append(folder) }
            }
        }
        return redirected
    }
}
