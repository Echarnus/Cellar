import Foundation

extension GameStore {
    /// The stores in the library's fixed order.
    public static var inLibraryOrder: [GameStore] { allCases.sorted { $0.sortIndex < $1.sortIndex } }
}
