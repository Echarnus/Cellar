import Foundation
import IOKit.hid

/// Stopping a wheel's motor from outside the game.
///
/// Cellar's SDL drivers stop every force when SDL closes the wheel, but SDL lives in the bottle's
/// Wine processes, and those end with a SIGKILL — a crash, `wineserver -k`, the sweep after it — so
/// that close never runs. A Thrustmaster keeps playing an effect uploaded as infinite, and a Fanatec
/// base keeps the last force it was sent: the motor goes on pushing with nothing left to stop it.
/// So once a bottle's Wine is gone (`WineRunner.shutDown`), Cellar sends the stop the driver would
/// have sent.
extension CellarSDL {
    /// Stop every force on the Fanatec and Thrustmaster wheels Cellar's SDL drives. For the moment
    /// a bottle's Wine has gone: a game in another bottle loses its force feedback too, which is
    /// the price of a motor never being left running. Costs one HID listing when nothing is attached.
    public static func stopWheels() {
        guard shouldStopWheels(environment: ProcessInfo.processInfo.environment) else { return }
        for device in Wheels.controllerDevices() {
            let vendorID = Wheels.intProperty(device, kIOHIDVendorIDKey)
            let productID = Wheels.intProperty(device, kIOHIDProductIDKey)
            guard let stop = stopReports(vendorID: vendorID, productID: productID,
                                         fanatecReportID: vendorID == Wheels.Vendor.fanatec.vendorID ? firstOutputReportID(device) : 0),
                  IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
            let sent = stop.reports.filter {
                defer { Thread.sleep(forTimeInterval: 0.008) }   // a Thrustmaster drops faster commands
                return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, stop.reportID, $0, $0.count) == kIOReturnSuccess
            }.count
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            CellarLog.debug(.session, String(format: "Wheel %04x:%04x stopped: %d of %d reports taken.",
                                             vendorID, productID, sent, stop.reports.count))
        }
    }

    /// Whether this Cellar may touch the wheels: not with `CELLAR_FFB_DISABLE` set, read the way SDL
    /// reads the drivers' switch (with it, Cellar's SDL never drove the wheel), and not from a
    /// relocated Cellar (`CELLAR_HOME`): a test or a throwaway install leaves real hardware alone.
    static func shouldStopWheels(environment: [String: String]) -> Bool {
        let disable = environment["CELLAR_FFB_DISABLE"] ?? ""
        if !disable.isEmpty, disable != "0", disable.lowercased() != "false" { return false }
        return (environment["CELLAR_HOME"] ?? "").isEmpty
    }

    /// The output reports, as `IOHIDDeviceSetReport` takes them, that stop every force on a wheel
    /// Cellar's SDL drives; nil for any other device. The same bytes as the drivers' own paths
    /// (Shim/sdl/): a Thrustmaster's stop for each of its 16 effect slots and its close sequence
    /// (`CellarThrustmaster_Destroy`, which knows which slots play — from outside, all of them);
    /// a Fanatec base's five slots disabled, as at open, then its stop-all (`CellarFanatec_Destroy`).
    /// `fanatecReportID` is the base's first output report, as the driver finds it.
    static func stopReports(vendorID: Int, productID: Int,
                            fanatecReportID: Int) -> (reportID: CFIndex, reports: [[UInt8]])? {
        if vendorID == Wheels.Vendor.thrustmaster.vendorID,
           forceFeedbackProducts[.thrustmaster]?.contains(productID) == true {
            let length = productID == 0xB66D ? 31 : 63   // CellarThrustmaster_BufferLength: PS4 mode
            func report(_ bytes: [UInt8]) -> [UInt8] { [0x60] + bytes + [UInt8](repeating: 0, count: length - bytes.count) }
            let stops = (1...16).map { report([0x00, UInt8($0), 0x89]) }
            let isT300 = [0xB66E, 0xB66F, 0xB66D].contains(productID)
            let close = isT300 ? [report([0x01, 0x00])] : [report([0x01, 0x05]), report([0x01, 0x00])]
            return (0x60, stops + close)
        }
        if vendorID == Wheels.Vendor.fanatec.vendorID,
           forceFeedbackProducts[.fanatec]?.contains(productID) == true {
            let commands: [[UInt8]] = [
                [0x03, 0x08, 0, 0, 0, 0, 0], [0x13, 0x0B, 0, 0, 0, 0, 0],
                [0x23, 0x0C, 0, 0, 0, 0, 0xFF], [0x33, 0x0C, 0, 0, 0, 0, 0xFF], [0x43, 0x0C, 0, 0, 0, 0, 0xFF],
                [0xF3, 0, 0, 0, 0, 0, 0],
            ]
            // With report IDs, macOS expects the ID as the first byte (CellarFanatecSend).
            let id = UInt8(truncatingIfNeeded: fanatecReportID)
            return (CFIndex(id), id == 0 ? commands : commands.map { [id] + $0 })
        }
        return nil
    }

    /// The ID of a device's first output report; 1 when it lists none (CellarFanatecReportID).
    private static func firstOutputReportID(_ device: IOHIDDevice) -> Int {
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
            as? [IOHIDElement] ?? []
        return elements.first { IOHIDElementGetType($0) == kIOHIDElementTypeOutput }
            .map { Int(IOHIDElementGetReportID($0)) } ?? 1
    }
}
