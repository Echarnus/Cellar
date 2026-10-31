import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Racing wheels and the controller checks around them: which HID devices count as sim-racing
/// hardware, what a player is told to do outside Cellar, and what `cellar doctor` says in each state.
@Suite(.serialized)
struct WheelsTests {

    @Test("Fanatec and MOZA devices are wheels unless their name says pedals, shifter or handbrake")
    func racingOnlyVendors() {
        #expect(Wheels.classify(vendorID: 0x0EB7, productID: 0x0020, product: "FANATEC CSL DD")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x0EB7, productID: 0x6204, product: "FANATEC CSL Pedals")?.kind == .pedals)
        #expect(Wheels.classify(vendorID: 0x0EB7, productID: 0x1A92, product: "ClubSport Shifter SQ")?.kind == .shifter)
        #expect(Wheels.classify(vendorID: 0x346E, productID: 0x0004, product: "MOZA R5 Base")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x346E, productID: 0x0010, product: "MOZA HBP Handbrake")?.kind == .handbrake)
        // A nameless base still says whose it is.
        #expect(Wheels.classify(vendorID: 0x0EB7, productID: 0x0001, product: "  ")?.name == "Fanatec wheel")
    }

    @Test("A Logitech or Thrustmaster device is a wheel only when its name says so")
    func mixedVendors() {
        #expect(Wheels.classify(vendorID: 0x046D, productID: 0xC24F, product: "G29 Driving Force Racing Wheel")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x046D, productID: 0xC262, product: "Logitech G920")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x044F, productID: 0xB66E, product: "Thrustmaster T300RS Racing wheel")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x044F, productID: 0xB65D, product: "Thrustmaster FFB Wheel")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x044F, productID: 0xB678, product: "T3PA")?.kind == .pedals)
        // The same makers' pads, sticks and mice are not wheels.
        #expect(Wheels.classify(vendorID: 0x046D, productID: 0xC21D, product: "Gamepad F310") == nil)
        #expect(Wheels.classify(vendorID: 0x044F, productID: 0xB10A, product: "T.16000M") == nil)
        #expect(Wheels.classify(vendorID: 0x046D, productID: 0xC08B, product: "G502 HERO Gaming Mouse") == nil)
        // "tx" is a model only as a whole word.
        #expect(Wheels.classify(vendorID: 0x044F, productID: 0x0001, product: "Thrustmaster TX Racing Wheel")?.kind == .wheel)
        #expect(Wheels.classify(vendorID: 0x046D, productID: 0x0001, product: "Logitech Extreme 3D Pro") == nil)
    }

    @Test("Hardware from any other maker is left alone")
    func unknownVendor() {
        #expect(Wheels.classify(vendorID: 0x045E, productID: 0x0B13, product: "Xbox Wireless Controller") == nil)
        #expect(Wheels.Vendor(vendorID: 0x054C) == nil)
    }

    @Test("Every vendor tells the player what to do outside Cellar, and none claims force feedback")
    func setupGuidance() {
        for vendor in Wheels.Vendor.allCases {
            #expect(!vendor.setup.isEmpty, "\(vendor) has no set-up guidance")
            for step in vendor.setup {
                #expect(!step.lowercased().contains("force feedback works"), "\(vendor) promises force feedback")
                #expect(step.hasSuffix("."), "a step is a sentence: \(step)")
            }
        }
        #expect(Wheels.Vendor.fanatec.setup.joined().contains("PC mode"))
        #expect(Wheels.Vendor.fanatec.setup.joined().contains("Windows PC"))
        #expect(Wheels.forceFeedbackNote.contains("no force feedback"))
    }

    @Test("Input Monitoring is never a ✓ until macOS has said yes")
    func inputMonitoring() {
        let granted = Controllers.inputMonitoringCheck(.granted, who: "Cellar")
        #expect(granted.status == .ok && granted.hint == nil)
        let notAsked = Controllers.inputMonitoringCheck(.notAsked, who: "Cellar")
        #expect(notAsked.status == .info)
        #expect(notAsked.hint?.contains("Allow it") == true)
        let denied = Controllers.inputMonitoringCheck(.denied, who: "this terminal")
        #expect(denied.status == .warn)
        #expect(denied.detail.contains("this terminal"))
        #expect(denied.hint?.contains("Privacy & Security → Input Monitoring") == true)
    }

    @Test("A runner's SDL is found where its Wine looks for libraries, and only there")
    func runnerSDL() throws {
        let root = TestHome.scratch("runner-sdl")
        let lib = root.appendingPathComponent("wine/lib", isDirectory: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        let install = RunnerInstall(spec: RunnerCatalog.wineforge, root: root,
                                    wineBinary: root.appendingPathComponent("wine/bin/wine"))
        let directories = Controllers.libraryDirectories(of: install)
        #expect(directories.contains(lib))
        #expect(Controllers.sdlLibrary(in: directories) == nil)

        try Data().write(to: lib.appendingPathComponent("libSDL2-2.0.0.dylib"))
        try Data().write(to: lib.appendingPathComponent("libSDL2.a"))
        #expect(Controllers.sdlLibrary(in: directories)?.lastPathComponent == "libSDL2-2.0.0.dylib")

        let found = Controllers.sdlCheck(runnerID: "wineforge", library: Controllers.sdlLibrary(in: directories))
        let missing = Controllers.sdlCheck(runnerID: "wineforge", library: nil)
        #expect(found.status == .info && missing.status == .info, "SDL on disk is a pointer, not proof")
        #expect(missing.detail.contains("no SDL"))
    }

    @Test("Doctor lists wheels only when one is connected, always says where Input Monitoring stands")
    func doctorRows() {
        let none = Controllers.doctorChecks(pads: [], wheels: [], inputMonitoring: .notAsked,
                                            who: "Cellar", runnerLayer: nil)
        #expect(none.map(\.name) == ["Controllers", "Input Monitoring"])
        #expect(none[0].detail == "none connected")

        let wheel = Wheels.classify(vendorID: 0x0EB7, productID: 0x0020, product: "FANATEC CSL DD")!
        let pad = Controllers.Pad(name: "DualSense Wireless Controller", kind: .dualSense)
        let some = Controllers.doctorChecks(pads: [pad], wheels: [wheel], inputMonitoring: .granted, who: "Cellar",
                                            runnerLayer: Controllers.sdlCheck(runnerID: "wineforge", library: nil))
        #expect(some.map(\.name) == ["Controllers", "Racing wheels", "Input Monitoring", "Controller layer"])
        #expect(some[1].detail.contains("FANATEC CSL DD (Fanatec wheel)"))
        #expect(some[1].hint?.contains("cellar controllers") == true)
        #expect(some.filter { $0.name != "Input Monitoring" }.allSatisfy { $0.status == .info },
                "a connected device is never a ✓: Cellar cannot see whether the game takes it")
    }

    @Test("The site's FAQ covers every wheel maker Cellar recognises, and the same limit on force feedback")
    func faqMatches() throws {
        let site = try String(contentsOf: Repo.root.appendingPathComponent("pages/gen-site.py"), encoding: .utf8)
        #expect(site.contains("\"controllers\""), "the app links to faq.html#controllers")
        for vendor in Wheels.Vendor.allCases {
            #expect(site.contains("<b>\(vendor.displayName)</b>"), "the FAQ has no set-up steps for \(vendor.displayName)")
        }
        #expect(site.contains("Force feedback depends on the wheel"))
        // Every wheel Cellar's SDL drives is named in the FAQ as driven.
        for (vendor, models) in CellarSDL.forceFeedbackWheels {
            #expect(site.contains("\(vendor.displayName) \(models)"), "the FAQ does not name \(vendor.displayName)'s driven wheels")
        }
        #expect(site.contains("Input Monitoring"))
    }
}
