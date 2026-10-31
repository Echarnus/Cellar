import Foundation

public enum CellarError: Error, LocalizedError, CustomStringConvertible {
    case notImplemented(String)
    case invalidArgument(String)
    case ioFailure(String)

    public var description: String {
        switch self {
        case .notImplemented(let message): return message
        case .invalidArgument(let message): return message
        case .ioFailure(let message): return message
        }
    }

    public var errorDescription: String? { description }
}
