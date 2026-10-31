import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Save backups handed an environment instead of reading `CELLAR_HOME`: each test has a home of its
/// own and a clock it chose, so these run in parallel and never touch the process environment.
struct CellarEnvironmentTests {

    /// A fresh directory with a bottle in it holding one save, and an environment rooted beside it.
    private func sandbox(at time: Date) throws -> (environment: CellarEnvironment, bottle: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cellar-env-\(UUID().uuidString)", isDirectory: true)
        let bottle = root.appendingPathComponent("bottles/env-\(UUID().uuidString.prefix(8))".lowercased(),
                                                 isDirectory: true)
        let save = bottle.appendingPathComponent("drive_c/users/steamuser/Saved Games/Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try Data("slot".utf8).write(to: save.appendingPathComponent("game.sav"))
        let environment = CellarEnvironment(home: root.appendingPathComponent("home", isDirectory: true),
                                            now: { time })
        return (environment, bottle)
    }

    @Test("A backup lands in the environment's home and is named by the environment's clock")
    func homeAndClock() throws {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let (environment, bottle) = try sandbox(at: time)
        defer { try? FileManager.default.removeItem(at: environment.home.deletingLastPathComponent()) }

        let backup = try #require(try SaveBackups.backUp(bottle: bottle, reason: .manual, in: environment))
        #expect(backup.url.path.hasPrefix(environment.saveBackups.path))
        #expect(backup.manifest.created == time)
        #expect(SaveBackups.list(bottle: bottle.lastPathComponent, in: environment).map(\.id) == [backup.id])
    }

    @Test("Two homes at once keep their backups apart")
    func twoHomes() throws {
        let (first, bottle) = try sandbox(at: Date(timeIntervalSince1970: 1_800_000_000))
        let second = CellarEnvironment(home: first.home.deletingLastPathComponent()
                                        .appendingPathComponent("other-home", isDirectory: true))
        defer { try? FileManager.default.removeItem(at: first.home.deletingLastPathComponent()) }

        try SaveBackups.backUp(bottle: bottle, reason: .manual, in: first)
        #expect(SaveBackups.list(bottle: bottle.lastPathComponent, in: first).count == 1)
        #expect(SaveBackups.list(bottle: bottle.lastPathComponent, in: second).isEmpty)
    }

    @Test("Live is the player's real home, so every call site that passes nothing is unchanged")
    func live() {
        #expect(CellarEnvironment.live.home == Paths.appSupport)
        #expect(CellarEnvironment.live.saveBackups == Paths.saveBackups)
    }
}
