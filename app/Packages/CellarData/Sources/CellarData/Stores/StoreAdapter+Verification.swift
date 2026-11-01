import CellarDomain
import Foundation

/// What a store without a session record of its own answers `cellar verify` (#203).
///
/// Battle.net does not publish who is signed in, and GOG runs no client in the bottle. So a sign-in
/// check there can't be done, and says so. It is never a pass. Steam's adapter answers from
/// Steam's own logs instead (`SteamSessionCheck`).
public extension StoreAdapter {
    func verificationMark(_ plan: GamePlan) -> UInt64 { 0 }

    func verificationChecks(_ plan: GamePlan, since mark: UInt64, launchSteps: [String]) -> [VerificationCheck] {
        guard store.descriptor.installsClientInBottle else { return [] }
        return [VerificationCheck(
            id: "signed-in", title: "\(store.descriptor.displayName) is signed in, with no sign-in window",
            verdict: .couldNotCheck,
            detail: "\(store.descriptor.displayName) doesn't record who is signed in where Cellar can read it.")]
    }

    func shutDownClient(_ plan: GamePlan, wine: WineRunner) { wine.shutDown() }
}
