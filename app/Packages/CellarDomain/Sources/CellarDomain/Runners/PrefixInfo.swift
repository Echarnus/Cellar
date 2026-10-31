import Foundation

public struct PrefixInfo {
    public let name: String
    public let url: URL
    public let backend: String
    public let runner: String

    public init(name: String, url: URL, backend: String, runner: String) {
        self.name = name
        self.url = url
        self.backend = backend
        self.runner = runner
    }
}
