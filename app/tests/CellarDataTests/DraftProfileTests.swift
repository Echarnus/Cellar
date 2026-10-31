import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Profiles Cellar writes itself for installed games nobody profiled: the PE header read right,
/// the exe picked right, and a draft that never claims to be tested.
@Suite(.serialized)
struct DraftProfileTests {

    /// A minimal, well-formed PE: one section holding the import descriptors and the DLL names.
    static func pe(machine: UInt16 = 0x8664, plus: Bool = true, imports: [String]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x400)
        func put16(_ value: Int, at: Int) { bytes[at] = UInt8(value & 0xFF); bytes[at + 1] = UInt8(value >> 8 & 0xFF) }
        func put32(_ value: Int, at: Int) { for i in 0..<4 { bytes[at + i] = UInt8(value >> (8 * i) & 0xFF) } }
        bytes[0] = 0x4D; bytes[1] = 0x5A
        put32(0x40, at: 0x3C)
        bytes[0x40] = 0x50; bytes[0x41] = 0x45
        put16(Int(machine), at: 0x44)
        put16(1, at: 0x46)                                   // one section
        let optionalSize = plus ? 240 : 224
        put16(optionalSize, at: 0x54)
        let optional = 0x58
        put16(plus ? 0x20B : 0x10B, at: optional)
        let directories = optional + (plus ? 112 : 96)
        put32(0x1000, at: directories + 8)                   // import table RVA
        put32(20 * (imports.count + 1), at: directories + 12)
        let section = optional + optionalSize
        put32(0x200, at: section + 8)                        // virtual size
        put32(0x1000, at: section + 12)                      // virtual address
        put32(0x200, at: section + 16)                       // raw size
        put32(0x200, at: section + 20)                       // raw pointer
        var nameRVA = 0x1100
        for (index, name) in imports.enumerated() {
            put32(nameRVA, at: 0x200 + index * 20 + 12)
            let offset = nameRVA - 0x1000 + 0x200
            for (i, byte) in name.utf8.enumerated() { bytes[offset + i] = byte }
            nameRVA += name.utf8.count + 1
        }
        return Data(bytes)
    }

    @Test("The machine and the imported DLLs are read from a PE32+ and a PE32")
    func readsHeaders() throws {
        let image = try #require(PEImage.parse(Self.pe(imports: ["KERNEL32.dll", "d3d11.dll", "XINPUT1_3.dll"])))
        #expect(image.machine == .x64)
        #expect(image.imports == ["kernel32.dll", "d3d11.dll", "xinput1_3.dll"])

        let old = try #require(PEImage.parse(Self.pe(machine: 0x014C, plus: false, imports: ["d3d9.dll"])))
        #expect(old.machine == .x86)
        #expect(old.imports == ["d3d9.dll"])
    }

    @Test("Something that isn't a PE reads as nil, not as a guess")
    func rejectsNonPE() {
        #expect(PEImage.parse(Data("MZ but not really".utf8)) == nil)
        var broken = [UInt8](Self.pe(imports: ["d3d11.dll"]))
        broken[0x40] = 0x00                                  // no "PE\0\0" signature
        #expect(PEImage.parse(Data(broken)) == nil)
        #expect(PEImage.parse(Data()) == nil)
    }

    @Test("The graphics API comes from the strongest import, and picks a backend that can run it")
    func graphicsAPI() {
        #expect(DetectedGraphicsAPI.detect(imports: ["d3d11.dll", "d3d12.dll"]) == .d3d12)
        #expect(DetectedGraphicsAPI.detect(imports: ["D3D11.DLL"]) == .d3d11)
        #expect(DetectedGraphicsAPI.detect(imports: ["d3d9.dll"]) == .d3d9)
        #expect(DetectedGraphicsAPI.detect(imports: ["vulkan-1.dll"]) == .vulkan)
        #expect(DetectedGraphicsAPI.detect(imports: ["kernel32.dll"]) == .unknown)
        #expect(DetectedGraphicsAPI.d3d9.backends.backend != .d3dmetal, "D3DMetal has no DX9")
        #expect(DetectedGraphicsAPI.d3d12.backends.fallback == .vkd3d, "DXVK has no DX12")
    }

    @Test("The game's exe is picked over installers, crash reporters and bootstraps")
    func picksExe() {
        let sizes: [String: Int64] = ["unins000.exe": 900_000_000, "CrashReporter.exe": 1,
                                      "Game.exe": 10, "Game/Binaries/Win64/Game-Win64-Shipping.exe": 5,
                                      "_CommonRedist/vcredist_x64.exe": 50]
        #expect(DraftProfile.pickExe(Array(sizes.keys), name: "Game", sizes: sizes)
                == "Game/Binaries/Win64/Game-Win64-Shipping.exe")
        let plain: [String: Int64] = ["Tool.exe": 900, "Hollow Knight.exe": 100, "UnityCrashHandler64.exe": 2_000]
        #expect(DraftProfile.pickExe(Array(plain.keys), name: "Hollow Knight", sizes: plain) == "Hollow Knight.exe")
        #expect(DraftProfile.pickExe(["setup.exe", "unins000.exe"], name: "X", sizes: [:]) == nil)
    }

    @Test("An installed game with no profile becomes an untested draft the rest of Cellar can read")
    func writesDraft() throws {
        TestHome.ensure()
        let library = TestHome.scratch("steamapps")
        let root = library.appendingPathComponent("common/Fixture Quest", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.pe(imports: ["kernel32.dll", "d3d9.dll"]).write(to: root.appendingPathComponent("FixtureQuest.exe"))
        try Data("x".utf8).write(to: root.appendingPathComponent("unins000.exe"))
        let appID = 990_000 + Int.random(in: 0..<9_999)
        try """
        "AppState"
        {
            "appid"        "\(appID)"
            "name"         "Fixture Quest \(appID)"
            "installdir"   "Fixture Quest"
        }
        """.write(to: library.appendingPathComponent("appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)

        let candidates = DraftProfile.candidates(steamLibrary: library, profiledAppIDs: [])
        let candidate = try #require(candidates.first { $0.steamAppID == appID })
        #expect(DraftProfile.candidates(steamLibrary: library, profiledAppIDs: [appID]).isEmpty,
                "a game that has a profile is not a candidate")

        let slug = try DraftProfile.write(candidate)
        defer { try? FileManager.default.removeItem(at: Paths.userProfiles.appendingPathComponent("\(slug).toml")) }
        let plan = try Game.plan(slug: slug)
        #expect(plan.isDraft)
        #expect(plan.facts.status == "untested")
        #expect(plan.launchExe == "FixtureQuest.exe")
        #expect(plan.installDir == "Fixture Quest")
        #expect(plan.appID == appID)
        #expect(plan.store == .steam)
        #expect(plan.backend == "dxvk")
        #expect(plan.fallbackBackend == "wined3d")
        #expect(plan.facts.graphicsAPI == "DirectX 9")
    }
}
