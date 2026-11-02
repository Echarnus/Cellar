# Regressions

Every bug Cellar fixed, and the automated test that keeps it fixed. Kenneth's rule (2026-11-02):
each fix and each lesson gets a test, so the same bug can never reach him twice.

**Adding a fix?** Add its row here in the same PR, naming the test that fails without the fix.
`app/tests/Scripts/test_scripts.py` (`RegressionLedgerTests`) checks that every test named here
exists, and every release runs all of them (`release.yml`: the suite and the Wine tiers) before it
ships. Use `cellar verify` checks (`G1`–`G9` in [`DELIVERY-CHECKLIST.md`](DELIVERY-CHECKLIST.md))
for what only a real game shows.

| Fixed in | What broke | Kept fixed by |
|---|---|---|
| #261 | Planet Coaster 2's Workshop never loaded (stock wineserver) | `RunnerIntegrityTests.swift` › `stockWineserverIsDamage` |
| #248 | macOS killed every game: the copied loader's signature broke | `GameAppTests.swift` › `resignsTheCopiedLoader` |
| #236 | Steam asked to sign in again after it hung | `SteamClientSignInTests.swift` › `silentThenLoggedOnAfterRestart` |
| #236 | Fallout Shelter offline: started without Steam running | `FalloutShelterTests.swift` › `steamGameNeedsLiveSession` |
| #201 | Steam showed in the Dock while a game ran | `DockShimTests.swift` › `clientStartedForAGameIsHidden` |
| #220 | The Dock said `fallout-shelter`, not Fallout Shelter | `GameAppTests.swift` › `bundleTakesTheGamesName` |
| #242 | The keychain asked for the password after every build | `test_scripts.py` › `test_an_apple_development_identity_is_used` |
| #186 | A downloaded game couldn't see its DLC | `SteamLibraryEntryTests.swift` › `registersDownloadedCopy` |
| #212 | A test run overwrote the real runner with a fake Wine | `CellarSandboxTests.swift` › `cloneIsIndependent` |
| #239 | A game could read the tokens of the shell that started it | `CredentialStorageTests.swift` › `noTokenAtTheProcessBoundary` |
| #250 | A stopped `cellar verify` left no report and the game running | `VerificationTests.swift` › `interruptedRun` |
| #258 | `cellar verify` passed a failed Frontier account call | `VerificationTests.swift` › `onlineErrorsFailGameOnline` |
