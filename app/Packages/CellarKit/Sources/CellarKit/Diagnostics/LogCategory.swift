import CellarDomain
import Foundation

/// What part of Cellar an entry came from. Kept coarse: enough to filter by, not a taxonomy.
public enum LogCategory: String, CaseIterable {
    case app         // the GUI and the CLI themselves: started, quit, command invoked
    case session     // one play session: launched, exited after N minutes
    case launch      // getting a game to start
    case setup       // runner + bottle + store client
    case install     // downloading/installing a game
    case store       // Steam / Battle.net / GOG client work
    case account     // sign-in state
    case runner      // runner install / removal
    case prefix      // bottle work
    case diagnostics // the log about the log: rotation, export
}
