import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// `SystemEnvironment.thisMac` is a `static let` a game's page reads from its view body. It once ran
/// `sysctl` through `Shell.run`, whose `waitUntilExit` spins the main run loop: SwiftUI re-entered
/// the body, reached the same `dispatch_once` and Cellar crashed opening a game's page (#340).
struct SystemEnvironmentTests {

    /// The declaration of `name` in SystemEnvironment.swift, up to the first blank line after it.
    private static func declaration(_ name: String) throws -> String {
        let file = Repo.source("CellarData/System/SystemEnvironment.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let start = try #require(text.range(of: name), "SystemEnvironment.swift no longer declares \(name)")
        let rest = text[start.lowerBound...]
        let end = rest.range(of: "\n\n")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    @Test("This Mac is read without starting a process, so a view body can read it",
          arguments: ["public static let thisMac", "public static var chipBrand", "public static var isAppleSilicon",
                      "static func sysctlString", "static func sysctlInt"])
    func thisMacStartsNoProcess(_ name: String) throws {
        let body = try Self.declaration(name)
        for api in ["Shell.", "Process(", "waitUntilExit", "RunLoop"] {
            #expect(!body.contains(api), "\(name) uses \(api): a view body reaching it re-enters itself")
        }
    }

    @Test("The chip name and the Apple Silicon flag match what sysctl prints")
    func matchesSysctl() {
        let brand = Shell.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(SystemEnvironment.chipBrand == brand)
        #expect(!SystemEnvironment.chipBrand.isEmpty)

        let arm64 = Shell.run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(SystemEnvironment.isAppleSilicon == (arm64 == "1"))
    }

    @Test("A name this Mac does not have reads as nothing, not as a crash or an empty value")
    func unknownName() {
        #expect(SystemEnvironment.sysctlString("cellar.no.such.name") == nil)
        #expect(SystemEnvironment.sysctlInt("cellar.no.such.name") == nil)
    }

    @Test("This Mac carries the chip it reads and the memory it has")
    func thisMacIsFilledIn() {
        let mac = SystemEnvironment.thisMac
        #expect(mac.chip == MacChip(SystemEnvironment.chipBrand))
        #expect(mac.memoryGB == Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
        #expect(mac.memoryGB > 0)
    }

    /// The same rule for the app: a view's body is where a process start does the damage.
    @Test("No view in the app starts a process")
    func viewsStartNoProcess() throws {
        for (file, text) in try ArchitectureTests.sources(in: "CellarApp") where file.hasSuffix("View.swift") {
            for api in ["Shell.run", "Shell.which", "Process("] {
                #expect(!text.contains(api), "CellarApp/\(file) uses \(api)")
            }
        }
    }
}
