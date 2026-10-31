import Foundation

/// How a launch was actually carried out — the CLI needs this to say the right thing afterwards
/// and to know what to wait on.
public enum LaunchRoute: Equatable, Sendable {
    case direct(exeName: String)
    /// The exe started by Cellar with the bottle's Steam client up beside it for the game's DRM —
    /// a Steam game Cellar downloaded itself. Started like `direct`, but there is a client to close.
    case steamAlongside(exeName: String, appID: Int)
    case steam(appID: Int)
    case battlenet(product: String)

    /// How the route reads in the log and in a diagnostics report.
    public var logDescription: String {
        switch self {
        case .direct(let exeName):    return "direct: \(exeName)"
        case .steamAlongside(let exeName, let appID):
            return "beside Steam: \(exeName), AppID \(appID)"
        case .steam(let appID):       return "via Steam, AppID \(appID)"
        case .battlenet(let product): return "via Battle.net, product \(product)"
        }
    }
}
