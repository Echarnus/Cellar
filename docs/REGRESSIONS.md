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
| #347 | The 0.6.8 release stopped after every test passed: building the installer disk image hit a busy disk once (`hdiutil: Resource busy`) | `test_scripts.py` › `test_busy_disk_is_retried` |
| #345 | Steam refused the saved sign-in minutes after signing in: 0.6.7 traded it for Steam's library list at every launch, often several times within seconds | `LibraryRecheckTests.swift` › `launchAsksOnlyWhenAnHourOld`, `asksMomentsApartReuseTheAnswer`, `appUsesTheLaunchRule` |
| #330 | macOS kept asking to let `cellar` use the Steam sign-in in the keychain, after every new build of the CLI | `SteamTokenVaultTests.swift` › `launchPathNeverTouchesKeychain`, `steamSourcesNeverReadTheKeychain`, `migratesOnce` |
| #332 | Opening a game's page crashed the app: reading this Mac's chip started `sysctl`, whose wait let the page redraw inside a one-time initialiser | `ThisMacTests.swift` › `readsWithoutTheRunLoop`, `watchCatchesAProcess` |
| #343 | A game added by an update (Theme Hospital, in 0.6.5) never showed in the library: Steam was only asked again at sign-in | `LibraryRecheckTests.swift` › `newProfileIsAskedAbout`, `appAsksWhenDue`, `pullFiresOncePerGesture` |
| #325 | A game started in Cellar's folder instead of its own, so one that opens its files by relative path (Theme Hospital's DOSBox and its settings) found none of them | `LaunchLifecycleTests.swift` › `gameStartsInItsOwnFolder`, `alongsideStartsInItsOwnFolder` |
| #310 | Skyrim opened in a small titled window instead of full screen | `DisplayIniTests.swift` › `skyrimFileIsFixed` |
| #310 | Skyrim, GTA V, Stardew Valley and The Witcher 3 showed Metal's frame-rate overlay to every player | `DisplayIniTests.swift` › `noProfileShowsTheOverlay` |
| #309 | A game with DLC depots filled the download bar to 100% once per depot (Dark Souls III looked like it downloaded three times) | `DepotDownloadProgressTests.swift` › `oneBarAcrossDepots` |
| #309 | A resumed download called checking the files already on disk "Downloading" | `DownloadProgressIntegrationTests.swift` › `resumedDownload` |
| #309 | A downloading game's page showed a greyed-out Install and "The last download stopped before it finished" | `GameSummaryTests.swift` › `noButtonWhileDownloading` |
| #304 | An uninstalled game still said "Installed": only one of its copies was removed (Cellar's download, not the Steam client's own) | `UninstallEveryCopyTests.swift` › `removesEveryCopy` |
| #304 | Right-clicking a game offered only Play and Settings, not Uninstall and the rest of the "…" menu | `GameMenuTests.swift` › `bothMenusShareTheContent` |
| #278 | Players without the Steam mobile app couldn't sign in to Steam (QR was the only way) | `SteamPasswordSignInTests.swift` › `conversesOverStdin` |
| #278 | A Steam password could reach a command line | `SteamPasswordSignInTests.swift` › `passwordNeverAnArgument` |
| #281 | Shipped releases (0.4.1, 0.4.2) left their "Release Cellar" issue open | `test_scripts.py` › `test_release_workflow_runs_it_after_publishing` |
| #267 | GTA V's Rockstar launcher said "wine" in the Dock | `DockShimTests.swift` › `launcherWearsTheGamesName` |
| #267 | The uninstall dialog showed a Terminal command and bottle names | `RemovalSummaryTests.swift` › `plainWords` |
| #267 | The sidebar said "Sign in" to a signed-in player while loading | `SidebarAccountTests.swift` › `loading` |
| #267 | The library filter's segments changed width with the selection | `EqualSegmentedPickerTests.swift` › `stableAcrossSelection` |
| #272 | Free-to-play games the player never added showed in the library | `SteamOwnershipCheckTests.swift` › `claimedFreeIsNotOwned` |
| #288 | Free games with a licence but never played showed in the library | `SteamOwnershipCheckTests.swift` › `libraryFollowsSteamsList` |
| #244 | Steam's error reporter opened over Fallout Shelter: Wine on macOS dropped the packet-priority message Steam's networking asks for | `recvtos-test.c` › `real_packet` |
| #246 | Skyrim closed at once: the settings files its launcher writes were never made | `FirstRunFilesTests.swift` › `playWritesThemFirst` |
| #246 | Skyrim's downloaded copy never reached Steam's library while another game's Steam was open | `SteamLibraryEntryOrderTests.swift` › `registersAfterTheHandOverAndBeforeTheClient` |
| #246 | Skyrim crashed on D3DMetal 3.0 even with its settings; it needs D3DMetal 4 | `FirstRunFilesTests.swift` › `skyrimProfile` |
| #246 | Every game's failed start read as Planet Coaster 2 hitting "the D3DMetal startup race" | `StartSupervisorTests.swift` › `givingUpNamesTheGame` |
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
| #270 | A second Ctrl-C (or SIGTERM after SIGINT) during `cellar verify` left the bottle's Steam and wineserver running and the report saying "still running" | `VerificationTests.swift` › `stoppedAtOnce` |
| #273 | Even one Ctrl-C ended `cellar verify` at once: the CLI's process-wide stop re-raised the signal before verify's own teardown ran, leaving Steam and wineserver running | `ChildProcessesTests.swift` › `leaveStopToCommand` |
| #258 | `cellar verify` passed a failed Frontier account call | `VerificationTests.swift` › `onlineErrorsFailGameOnline` |
| #334 | Play started Assetto Corsa beside a Steam that was running but had never signed in (an earlier client's logon in the shared log was taken for its own), so the game never appeared | `RunningSteamSignInTests.swift` › `earlierClientsLogonIsNotThisOnes` |
| #334 | A start attempt that never came up left nothing to read: Wine ran with `-all` and the game log was empty | `RunningSteamSignInTests.swift` › `attemptLogSummary` |
| #334 | A DLC depot without a licence made the update check say "this account doesn't own it" | `RunningSteamSignInTests.swift` › `dlcDepotIsNotTheGame` |
| #349 | Theme Hospital (WineD3D) sat on "Opening Steam": Steam's browser had no Direct3D 11 under WineD3D, never drew its page, never signed in | `SteamClientStartTests.swift` › `wined3dClientRunsOnD3DMetal` |
| #349 | A Steam left running signed out by a cancelled launch made the next Play wait 90 s on it before restarting it | `RunningSteamSignInTests.swift` › `staleSignedOutClientIsRestarted` |
| #349 | "Your Steam sign-in is kept" was shown while the library said Steam had turned the sign-in down | `RunningSteamSignInTests.swift` › `failureWordingFollowsTheSignIn` |
