import Foundation
import IOKit.hid

/// Sim-racing hardware — wheel bases, pedals, shifters — and what a player has to do *outside*
/// Cellar to use it.
///
/// macOS's GameController framework only knows a couple of Logitech wheels (`GCRacingWheel`), so
/// Cellar reads the HID layer directly: anything that calls itself a joystick, gamepad or
/// multi-axis controller, sorted by the vendor that made it. Wine reads the same HID layer, so a
/// device listed here is one Wine can see. Whether a game takes it, and with what force feedback,
/// is a separate question, and Cellar never answers it with a ✓.
public enum Wheels {

    /// The makers whose hardware Cellar recognises, with what each needs from the player.
    public enum Vendor: String, Sendable, CaseIterable {
        case fanatec, logitech, thrustmaster, moza

        /// USB vendor IDs, as the hardware reports them.
        public var vendorID: Int {
            switch self {
            case .fanatec:      return 0x0EB7
            case .logitech:     return 0x046D
            case .thrustmaster: return 0x044F
            case .moza:         return 0x346E
            }
        }

        public var displayName: String {
            switch self {
            case .fanatec:      return "Fanatec"
            case .logitech:     return "Logitech"
            case .thrustmaster: return "Thrustmaster"
            case .moza:         return "MOZA"
            }
        }

        public init?(vendorID: Int) {
            guard let vendor = Vendor.allCases.first(where: { $0.vendorID == vendorID }) else { return nil }
            self = vendor
        }

        /// Logitech and Thrustmaster also make gamepads, flight sticks and mice, so for them the
        /// vendor alone does not make a device a wheel — its name has to say so. Fanatec and MOZA
        /// make nothing else.
        var onlyMakesRacingHardware: Bool { self == .fanatec || self == .moza }

        /// The things a player does outside Cellar, in the order worth doing them. Each is something
        /// the vendor's own documentation says, not a guess about what might help.
        public var setup: [String] {
            switch self {
            case .fanatec:
                return [
                    "Put the wheel base in PC mode, not Compatibility (PlayStation/Xbox) mode — its manual shows how for your base.",
                    "Update the firmware first on a Windows PC with Fanatec's own software. Fanatec offers no Mac app, and a base on old firmware may not show up at all.",
                ]
            case .logitech:
                return [
                    "macOS recognises the G29 and G920 on its own since Ventura; there is no driver to install.",
                    "Firmware updates go through Logitech G HUB. If it doesn't list your wheel on the Mac, update it once on a Windows PC.",
                ]
            case .thrustmaster:
                return [
                    "Set the base to its PC mode, as its manual describes, and connect it over USB.",
                    "Thrustmaster's drivers and firmware updates are Windows-only. Without that driver some bases report the pedals as buttons rather than axes, which most racing games cannot use.",
                ]
            case .moza:
                return [
                    "Update the firmware and set the steering angle in MOZA Pit House on a Windows PC first; the base keeps those settings.",
                ]
            }
        }
    }

    public enum Kind: String, Sendable {
        case wheel, pedals, shifter, handbrake

        public var displayName: String {
            switch self {
            case .wheel:     return "wheel"
            case .pedals:    return "pedals"
            case .shifter:   return "shifter"
            case .handbrake: return "handbrake"
            }
        }
    }

    public struct Device: Sendable, Equatable {
        public let name: String
        public let vendor: Vendor
        public let kind: Kind
        public let productID: Int
    }

    /// What force feedback a player can expect from a wheel Cellar's SDL does not drive. macOS hands
    /// force feedback to a device through a vendor plug-in (ForceFeedback.framework), and none of
    /// these vendors ships one for Apple Silicon, so for those wheels it is "steering and pedals, no
    /// feel" until Cellar's own driver covers them (`CellarSDL.forceFeedbackWheels`).
    public static let forceFeedbackNote =
        "Expect steering, pedals and buttons, but no force feedback yet: macOS needs a driver from the wheel's maker for that, none ships one for Apple Silicon Macs, and Cellar's own driver does not cover this wheel yet."

    /// Said instead of `forceFeedbackNote` for a wheel Cellar's own SDL drives.
    public static let drivenForceFeedbackNote =
        "Cellar drives this wheel's force feedback over USB itself. It is new: if it feels wrong, or too strong, say so in a report."

    /// The force-feedback sentence for what is connected: the hopeful one only when every wheel
    /// connected is one Cellar's SDL drives and that SDL is installed.
    public static func forceFeedbackNote(for devices: [Device], cellarSDL: Bool) -> String {
        let wheels = devices.filter { $0.kind == .wheel }
        guard cellarSDL, !wheels.isEmpty, wheels.allSatisfy(CellarSDL.drivesForceFeedback) else { return forceFeedbackNote }
        return drivenForceFeedbackNote
    }

    /// Sorts one HID device into sim-racing hardware, or nil for anything else. Pure, so the
    /// table is tested without the hardware.
    public static func classify(vendorID: Int, productID: Int, product: String) -> Device? {
        guard let vendor = Vendor(vendorID: vendorID) else { return nil }
        let name = product.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()
        let kind: Kind
        if lower.contains("pedal") || lower.contains("t3pa") || lower.contains("t-lcm") {
            kind = .pedals
        } else if lower.contains("shifter") || lower.contains("th8") || lower.contains("sequential") {
            kind = .shifter
        } else if lower.contains("handbrake") {
            kind = .handbrake
        } else if vendor.onlyMakesRacingHardware || looksLikeWheel(lower) {
            kind = .wheel
        } else {
            return nil
        }
        return Device(name: name.isEmpty ? "\(vendor.displayName) \(kind.displayName)" : name,
                      vendor: vendor, kind: kind, productID: productID)
    }

    /// Names Logitech and Thrustmaster give their wheels. Whole words for the short model codes, so
    /// a "T.16000M" flight stick or an "F310" gamepad is never read as a wheel.
    static func looksLikeWheel(_ lowercasedName: String) -> Bool {
        let phrases = ["wheel", "racing", "driving force", "momo"]
        if phrases.contains(where: { lowercasedName.contains($0) }) { return true }
        let models: Set<String> = ["g25", "g27", "g29", "g920", "g923", "rs50",
                                   "t150", "t248", "t300", "t300rs", "t500", "t500rs", "tmx", "tx",
                                   "t-gt", "ts-pc", "ts-xw", "t128", "t598", "t818", "t80"]
        let words = lowercasedName.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
        return words.contains(where: { models.contains($0) })
    }

    /// The sim-racing hardware connected now. Matches joysticks and pads only, never a keyboard,
    /// so it does not trigger macOS's Input Monitoring prompt.
    public static func connected() -> [Device] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let usages = [kHIDUsage_GD_Joystick, kHIDUsage_GD_GamePad, kHIDUsage_GD_MultiAxisController]
        let matching = usages.map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] as [String: Int]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        var devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        if devices.isEmpty {
            // Some macOS versions only enumerate once the manager is open. The matching names
            // joysticks and pads alone — never a keyboard — so opening it asks macOS for nothing.
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        var seen = Set<String>()
        return devices.compactMap { device -> Device? in
            let vendorID = intProperty(device, kIOHIDVendorIDKey)
            let productID = intProperty(device, kIOHIDProductIDKey)
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
            guard let found = classify(vendorID: vendorID, productID: productID, product: product) else { return nil }
            // One base can expose several HID interfaces; list it once.
            guard seen.insert("\(vendorID):\(productID)").inserted else { return nil }
            return found
        }
        .sorted { ($0.vendor.rawValue, $0.name) < ($1.vendor.rawValue, $1.name) }
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
}
