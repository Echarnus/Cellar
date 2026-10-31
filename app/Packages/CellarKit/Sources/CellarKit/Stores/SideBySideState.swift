import CellarDomain
import Foundation

/// The queue and the answers `StoreLibrary.askSideBySide` shares between its workers. Every access
/// goes through `lock`.
final class SideBySideState<Item: Hashable, Answer>: @unchecked Sendable {
    let lock = NSLock()
    var next = 0
    var answers: [Item: Answer] = [:]
}
