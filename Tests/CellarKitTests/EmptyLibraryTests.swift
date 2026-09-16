import Testing
@testable import CellarKit

/// What an empty library says. The bug these pin: a player who had just scanned Steam's QR code was
/// told "Sign in to see your games" for the seconds Steam spent answering which games they own.
struct EmptyLibraryTests {

    @Test("A check in progress wins over every other reading, including signed out")
    func checkingWins() {
        let sentence = "Asking Steam which of 8 games you own…"
        #expect(StoreLibrary.emptyLibrary(hasGames: false, checking: sentence, hasConnectedStore: true,
                                          uncheckedWithheld: 8) == .checking(sentence))
        // Accounts can know the sign-in succeeded a moment before the library re-reads it.
        #expect(StoreLibrary.emptyLibrary(hasGames: false, checking: sentence, hasConnectedStore: false,
                                          uncheckedWithheld: 0) == .checking(sentence))
    }

    @Test("Games hidden by a filter are a filter problem, whatever else is going on")
    func filteredIsNoMatches() {
        #expect(StoreLibrary.emptyLibrary(hasGames: true, checking: "Asking Steam…", hasConnectedStore: false,
                                          uncheckedWithheld: 3) == .noMatches)
    }

    @Test("Signed in but never asked is not 'none of your games are supported'")
    func uncheckedIsNotNothingOwned() {
        #expect(StoreLibrary.emptyLibrary(hasGames: false, checking: nil, hasConnectedStore: true,
                                          uncheckedWithheld: 4) == .unchecked)
        #expect(StoreLibrary.emptyLibrary(hasGames: false, checking: nil, hasConnectedStore: true,
                                          uncheckedWithheld: 0) == .nothingOwned)
    }

    @Test("Only a player with no store connected is asked to sign in")
    func signInOnlyWhenNothingConnected() {
        #expect(StoreLibrary.emptyLibrary(hasGames: false, checking: nil, hasConnectedStore: false,
                                          uncheckedWithheld: 8) == .signIn)
    }
}
