import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// The use cases (`LoadLibrary`, `SetUpGame`, `InstallGame`, `LaunchGame`, `UninstallGame`): their
/// dependencies really are swappable, and what they report arrives as one typed stream.
@Suite(.serialized)
struct UseCaseTests {

    /// A store that does nothing but say what it was asked to do, through the closures it was given.
    struct RecordingAdapter: StoreAdapter {
        var store: GameStore { .gog }
        func isClientInstalled(_ plan: GamePlan) -> Bool { true }
        var isClientRunning: Bool { false }
        func signedInAccount(_ plan: GamePlan) -> String? { nil }
        func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }
        func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                         phase: (InstallProgress) -> Void) throws {
            step("client set up")
        }
        func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                         progress: (String) -> Void, phase: (InstallProgress) -> Void) throws {
            phase(InstallProgress(.downloading))
            progress("tool output")
            step("installed \(plan.slug)")
        }
        func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws {}
        func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                                 progress: (String) -> Void, stage: (LaunchStage) -> Void,
                                 update: (InstallProgress) -> Void) throws -> LaunchRoute {
            stage(.running)
            return .direct(exeName: "fake.exe")
        }
    }

    // MARK: - Events

    @Test("Each event reaches the closure for its kind, and only that one")
    func deliver() {
        var lines: [String] = [], phases: [InstallProgress] = [], stages: [LaunchStage] = []
        for event in [GameEvent.step("hello"), .install(InstallProgress(.bottle)), .launch(.running)] {
            event.deliver(progress: { lines.append($0) }, install: { phases.append($0) },
                          launch: { stages.append($0) })
        }
        #expect(lines == ["hello"])
        #expect(phases == [InstallProgress(.bottle)])
        #expect(stages == [.running])
        #expect(GameEvent.step("x").sentence == "x")
        #expect(GameEvent.launch(.running).sentence == nil, "a stage is not a sentence to print")
    }

    // MARK: - Install

    @Test("InstallGame hands the work to the adapter it was given, and its reports arrive in order")
    func installUsesInjectedAdapter() throws {
        try #require(TestHome.installStubRunner() != nil)
        let plan = try TestHome.plan("[game]\nname = \"Use Case Game\"\nstore = \"gog\"", slug: "usecase-install")
        var events: [GameEvent] = []
        try InstallGame(plan, adapter: RecordingAdapter()).run { events.append($0) }
        #expect(events == [.install(InstallProgress(.downloading)), .step("tool output"),
                           .step("installed \(plan.slug)")])
    }

    @Test("The Game façade still splits the same stream back into its closures")
    func facadeMatchesUseCase() throws {
        try #require(TestHome.installStubRunner() != nil)
        let plan = try TestHome.plan("[game]\nname = \"Facade Game\"\nstore = \"gog\"", slug: "usecase-facade")
        var viaFacade: [String] = []
        var viaUseCase: [String] = []
        // No gog_product_id: both routes stop at the same sentence-free error, having said nothing.
        #expect(throws: CellarError.self) { try Game.installGame(plan) { viaFacade.append($0) } }
        #expect(throws: CellarError.self) { try InstallGame(plan).run { if let s = $0.sentence { viaUseCase.append(s) } } }
        #expect(viaFacade == viaUseCase)
    }

    // MARK: - Launch

    @Test("A launch says it is preparing before anything can fail")
    func launchReportsPreparingFirst() throws {
        let plan = try TestHome.plan("""
        [game]
        name  = "Launch Use Case Game"
        store = "gog"
        [runner]
        id = "no-such-runner"
        """, slug: "usecase-launch")
        var events: [GameEvent] = []
        #expect(throws: CellarError.self) { try LaunchGame(plan).run { events.append($0) } }
        #expect(events.first == .launch(.preparing))
    }

    // MARK: - Library

    @Test("LoadLibrary reads only the profiles it is given, and skips one that won't resolve")
    func loadLibraryUsesInjectedProfiles() throws {
        let plan = try TestHome.plan("[game]\nname = \"Library Use Case Game\"\nstore = \"gog\"", slug: "usecase-library")
        let library = LoadLibrary(slugs: { [plan.slug, "usecase-broken"] }, plan: { slug in
            guard slug == plan.slug else { throw CellarError.invalidArgument("no such profile") }
            return plan
        })
        #expect(library.summaries().map(\.slug) == [plan.slug])
    }

    // MARK: - Uninstall

    @Test("UninstallGame previews the same plan the removal engine draws up")
    func uninstallPreview() throws {
        let plan = try TestHome.plan("[game]\nname = \"Uninstall Use Case Game\"\nstore = \"gog\"", slug: "usecase-uninstall")
        let preview = UninstallGame(plan, scope: .game).preview()
        let direct = Uninstall.plan(for: plan, scope: .game)
        #expect(preview.items.map(\.url) == direct.items.map(\.url))
        #expect(preview.blockers == direct.blockers)
    }
}
