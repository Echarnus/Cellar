import CellarDomain
import AppKit
import CellarKit
import SwiftUI

/// Where the app sends a player for help. One table, so Settings and the Help menu never point at
/// two different pages.
enum Links {
    static let help = URL(string: "https://echarnus.github.io/Cellar/faq.html")!
    static let controllersHelp = URL(string: "https://echarnus.github.io/Cellar/faq.html#controllers")!
    static let supportedGames = URL(string: "https://echarnus.github.io/Cellar/")!
    static let repository = URL(string: "https://github.com/Echarnus/Cellar")!
    static let releases = URL(string: "https://github.com/Echarnus/Cellar/releases")!
    static let newIssue = URL(string: "https://github.com/Echarnus/Cellar/issues/new")!
}
