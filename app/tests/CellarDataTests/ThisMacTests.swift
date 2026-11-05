import CellarDomain
import CoreFoundation
import Foundation
import Testing
@testable import CellarData

/// Reading this Mac's chip must never spin the run loop (#332).
///
/// A game page reads `SystemEnvironment.thisMac` while it draws. Its chip name used to come from
/// starting `sysctl`, and `Shell.run`'s `waitUntilExit` spins the current run loop while it waits:
/// SwiftUI drew the page again inside `thisMac`'s one-time initialiser, the second read waited on
/// itself, and libdispatch crashed the app (EXC_BREAKPOINT in `_dispatch_once_wait`). These tests
/// watch the run loop of the thread doing the read, and prove the watch would have caught it.
@Suite(.serialized)
struct ThisMacTests {

    /// How many times `body` entered the current thread's run loop.
    static func runLoopEntries(during body: () -> Void) -> Int {
        var entries = 0
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.entry.rawValue, true, 0) { _, _ in
            entries += 1
        }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddObserver(loop, observer, .commonModes)
        CFRunLoopAddObserver(loop, observer, .defaultMode)
        defer {
            CFRunLoopRemoveObserver(loop, observer, .commonModes)
            CFRunLoopRemoveObserver(loop, observer, .defaultMode)
        }
        body()
        return entries
    }

    @Test("The watch catches a read that waits on a process, the way the crashing one did")
    func watchCatchesAProcess() {
        let entries = Self.runLoopEntries { _ = Shell.run("/bin/sleep", ["0.3"]) }
        #expect(entries > 0, "Shell.run spins the run loop: never call it where a view draws")
    }

    @Test("Reading this Mac's chip and memory never enters the run loop, so a page can't redraw inside it")
    func readsWithoutTheRunLoop() {
        var read: MacRequirements.ThisMac?
        let entries = Self.runLoopEntries {
            read = SystemEnvironment.readThisMac()
            _ = SystemEnvironment.chipBrand
        }
        #expect(entries == 0)
        #expect((read?.memoryGB ?? 0) > 0)
    }

    @Test("The chip name is read in-process, the same as sysctl prints it")
    func chipBrandIsTheMachines() {
        let brand = SystemEnvironment.chipBrand
        #expect(!brand.isEmpty)
        #expect(brand == Shell.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(SystemEnvironment.sysctlString("cellar.no.such.name") == nil)
    }
}
