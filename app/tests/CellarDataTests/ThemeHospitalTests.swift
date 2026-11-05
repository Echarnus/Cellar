import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Theme Hospital on Steam (#325): the 1997 DOS game in a DOSBox wrapper, released by Electronic
/// Arts on 2026-11-05. Steam starts `DOSBOX/Theme Hospital.exe` in the `DOSBOX` folder, so the
/// profile has to point there, and the launch has to start it there (`LaunchLifecycleTests`).
@Suite(.serialized)
struct ThemeHospitalTests {

    static func plan() throws -> GamePlan {
        _ = ProfileDatabaseTests.slugs   // stages the shipped profiles once
        return try Game.plan(slug: "theme-hospital")
    }

    @Test("The profile names Steam's own release: AppID, folder and the DOSBox program it starts")
    func steamRelease() throws {
        let plan = try Self.plan()
        #expect(plan.name == "Theme Hospital", "the Dock and the library show this name")
        #expect(plan.store == .steam)
        #expect(plan.appID == 2229820, "the AppID is what Steam is told about; a wrong one is someone else's game")
        #expect(plan.installDir == "Theme Hospital")
        #expect(plan.launchExe == "DOSBOX/Theme Hospital.exe")
        #expect(plan.startExe == nil, "Steam starts the DOSBox program itself, through no stub")
        #expect(plan.facts.status == "untested", "nobody has played it under Cellar yet")
    }

    @Test("DOSBox draws in 2D through OpenGL or DirectDraw, so Wine's own renderer draws it, with no dead fallback")
    func drawsWithWineD3D() throws {
        let plan = try Self.plan()
        #expect(plan.profileBackend == GraphicsBackend.wined3d.rawValue)
        #expect(plan.fallbackBackend == nil)
    }

    @Test("A copy the Steam client installed is found in its DOSBOX folder")
    func findsTheClientInstalledCopy() throws {
        let plan = try Self.plan()
        let fm = FileManager.default
        let exe = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/Theme Hospital/DOSBOX/Theme Hospital.exe")
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        try Data("MZ".utf8).write(to: exe)

        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(plan.directStartExe?.path == exe.path)
        #expect(!plan.canLaunchStoreFree, "it starts beside a running Steam, as Steam itself would")
    }
}
