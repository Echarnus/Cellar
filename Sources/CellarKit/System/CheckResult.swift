import CellarDomain
import Foundation

public struct CheckResult {
    public let name: String
    public let status: CheckStatus
    public let detail: String
    public let hint: String?

    public init(_ name: String, _ status: CheckStatus, _ detail: String, hint: String? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.hint = hint
    }
}
