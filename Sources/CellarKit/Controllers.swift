import Foundation
import GameController

/// Game controllers: which ones are connected, and what a game's profile says it does with one.
///
/// Wine hands a pad to a Windows game through SDL and its own winebus, which is a different path
/// from macOS's, so a pad macOS sees is not proof the game will. Cellar says what it can check —
/// what is connected — and what the profile records about the game; never "it works" on its own.
public enum Controllers {

    public enum Kind: String, Sendable, CaseIterable {
        case xbox, dualSense, dualShock, switchPro, other

        public var displayName: String {
            switch self {
            case .xbox:      return "Xbox controller"
            case .dualSense: return "DualSense"
            case .dualShock: return "DualShock 4"
            case .switchPro: return "Switch Pro Controller"
            case .other:     return "Controller"
            }
        }

        /// From `GCController.productCategory`, which names the family rather than the model.
        public init(productCategory: String) {
            let category = productCategory.lowercased()
            if category.contains("xbox") { self = .xbox }
            else if category.contains("dualsense") { self = .dualSense }
            else if category.contains("dualshock") { self = .dualShock }
            else if category.contains("switch") || category.contains("joy-con") { self = .switchPro }
            else { self = .other }
        }
    }

    public struct Pad: Sendable, Equatable {
        public let name: String
        public let kind: Kind
    }

    /// The controllers macOS sees now. A command-line process has no run loop turning while it
    /// starts, so it gives discovery a moment first; the app's has been running all along.
    public static func connected(settle: TimeInterval = 0) -> [Pad] {
        if settle > 0 { RunLoop.current.run(until: Date().addingTimeInterval(settle)) }
        return GCController.controllers().compactMap { controller in
            // Keyboards and mice can surface as GCController-adjacent devices; a pad has a gamepad profile.
            guard controller.extendedGamepad != nil || controller.microGamepad != nil else { return nil }
            let category = controller.productCategory
            return Pad(name: controller.vendorName ?? Kind(productCategory: category).displayName,
                       kind: Kind(productCategory: category))
        }
    }

    /// What a profile's `controller` field promises, in the player's words. Nil for no field: an
    /// unrecorded answer is shown as nothing rather than as a guess.
    public static func support(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        switch value {
        case "full":    return "Full controller support"
        case "partial": return "Partial: some screens need a mouse or keyboard"
        case "none":    return "Keyboard and mouse only"
        default:        return value
        }
    }

    /// Steam Input remaps a pad before the game sees it, so a Steam game launched through the
    /// client may behave differently from the same game started directly.
    public static func steamInputNote(store: GameStore, throughClient: Bool) -> String? {
        guard store == .steam, throughClient else { return nil }
        return "Started through Steam, so Steam Input may remap your controller. Change it in Steam's controller settings for this game."
    }
}
