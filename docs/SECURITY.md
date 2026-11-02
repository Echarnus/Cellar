# Security: where sign-ins live

Cellar signs in to real store accounts, so how it keeps those credentials is part of the product.
The bar is [OWASP MASVS v2](https://mas.owasp.org/MASVS/) **MASVS-STORAGE-1** (sensitive data is
stored securely) and **MASVS-STORAGE-2** (it does not leak — logs, backups, reports), applied with
Apple's Keychain Services guidance: the least permissive accessibility class that works, and
`ThisDeviceOnly` so a credential never migrates to another Mac.

## The inventory

| What | Where | Protection |
|---|---|---|
| GOG OAuth access + refresh token | Login keychain, service `it.clercq.cellar.gog` | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, labelled "Cellar — GOG sign-in". Read by the CLI only; the app asks `Keychain.contains` (attributes, no secret, no prompt). |
| Steam refresh token | Login keychain, service `it.clercq.cellar.steam`, between DepotDownloader runs (`SteamTokenVault`) | Restored to DepotDownloader's `account.config` (`0600`, out of backups) only while a run holds a lease, sealed back by the last run to end, deleted only once the keychain returns the exact bytes. A `0600` index beside it names the account and the token's public claims, so the app never reads the item. |
| Steam refresh token, DPAPI-wrapped | Each Steam bottle's `local.vdf` (`ConnectCache`) | `0600`, excluded from backups. The blob is recoverable by anyone holding the file — it is Wine's DPAPI — so it is treated as the token itself and taken back out on sign-out and reset. |
| Steam account name + dates | `shared/steam-account.json` | `0600` (`PrivateFiles.write`). Not a secret, but it says whose library this is. |
| GOG username | `shared/gog-account` | `0600`. One file both binaries read, so the app never fetches the name with the token. |
| Battle.net | — | Cellar holds nothing: Blizzard's client keeps its own session in the bottle. |
| Steam sign-in QR code (live while shown) | Only the Accounts panel that draws it (`QRCodePanel`) | Never kept as text: `ActivityStore` and every redaction pass (`Diagnostics.redactSignInCodes`) swap its rows for one placeholder line, so it reaches no activity pane, log or diagnostics report. (#165) |

## The rules

- **A credential goes in the keychain**, unless a third-party program needs it in its own file
  format — then that file is `0600`, out of backups, and named in the table above.
- **Nothing that is a credential reaches the log.** `CellarLog` runs every message through
  `Diagnostics.redactCredentials` before writing: JWTs (including Steam's `eyAi…` ones), `Bearer`
  values, `refresh_token`/`client_secret`/`password` values, OAuth `code=` parameters, and DPAPI hex
  blobs. The log itself is `0600` in a `0700` folder.
- **The report is redacted again, more broadly**, because it is meant to be posted in public:
  home paths, the macOS user name, the player's Steam and GOG account names, and any key that
  merely smells like a secret.
- **Command lines are redacted fail-closed** (`Diagnostics.redactCommandLine`): every option value
  is hidden unless it is on an allow-list.
- **Sign-out and reset leave nothing behind**: the keychain item (every account under the
  service), the cached name, DepotDownloader's token wherever it landed, and the session seeded
  into every bottle. A relocated Cellar (`CELLAR_HOME`) never touches the real keychain or token
  store.
- **Tests prove it.** `app/tests/CellarDataTests/CredentialStorageTests.swift` feeds real-shaped leaks
  through each path; `app/tests/CellarIntegrationTests/KeychainTests.swift` round-trips the real
  keychain under a throwaway service. A change that adds a place a credential can go adds a row
  above and a test there.

## Known limits, and what lifts them

- **The Steam token is on disk while DepotDownloader runs**, because that is the only place the tool
  reads it. If a run is killed, it stays there (private, out of backups) until the next run ends.
  `CELLAR_STEAM_TOKEN_VAULT=0` turns sealing off, for diagnosing a keychain problem.
- **An ad-hoc signed CLI asks for keychain access after each update.** The item trusts the binary
  that wrote it, and an ad-hoc signature changes with every build. A Developer ID signature fixes
  this for releases. A build from source (`install-app.sh`) is signed with the Mac's own
  "Apple Development" identity when there is one (`Scripts/local-sign-identity.sh`), with the fixed
  identifier `it.clercq.cellar.cli` on both copies of the CLI, so "Always Allow" is pressed once and
  holds across rebuilds. Without that identity it stays ad-hoc and the script says how to make one.
- **The app and the CLI do not share one keychain item.** On the login keychain an item trusts the
  binary that created it; a true shared item needs the data-protection keychain and a
  `keychain-access-groups` entitlement on both, signed with one Team ID. Until the Developer ID
  exists, the CLI is the only reader of secrets and the app only asks whether one exists.

# The whole app: threat model

Reviewed 2026-10-31 against Apple's *Platform Security Guide* (Gatekeeper, notarization, hardened
runtime, App Sandbox, Keychain) and the parts of [OWASP MASVS v2](https://mas.owasp.org/MASVS/)
that apply to a Mac app: STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE.

**What Cellar defends:** the player's store accounts, their Mac account (files, keychain), and the
integrity of the code Cellar puts on the Mac. **What it does not claim to defend:** a Windows game
from itself. Wine is a compatibility layer, not a sandbox; a game the player installed runs with
the player's rights, the way it would on Windows.

| Area | Status | How |
|---|---|---|
| Downloaded runners + DepotDownloader | ✅ | Pinned SHA-256 per file (`RunnerArtifact.sha256`, `DepotTool.downloadSHA256`), checked fresh *and* cached, before anything is unpacked or made executable (`Checksum`). Bumping a pin is a reviewed PR. SDL is pinned the same way in `app/Scripts/build-sdl.sh`. (#120) |
| Steam / Battle.net installers | Accepted risk | The vendors' own moving "latest" files on their HTTPS CDNs; they cannot be pinned. They run inside the bottle, not on the Mac side. |
| Transport | ✅ | Every `curl` is HTTPS-only, redirects included (`Downloader.httpsOnly`). (#121) |
| Secrets on command lines | ✅ | Tokens and refresh tokens go to curl on stdin (`--config -`), never argv, which every process can read. DepotDownloader never gets a password on argv. Cellar's own command lines are logged redacted, fail-closed. (#121) |
| Game database (#32) | ✅, off until keyed | Ed25519-signed bundle, key compiled in, refused without one; file names held to the slug alphabet; an older set can't replace a newer one. (#122, #124, #128) |
| What a child process inherits | ✅ | Wine, the store client, the game and DepotDownloader get an allow-list of the environment Cellar was started from (`ChildEnvironment`: `HOME`, `USER`, `TMPDIR`, the locale, `__CF_USER_TEXT_ENCODING`, `XPC_*`, `SDL_*`), never the rest, so a token in the shell or agent session that ran `cellar` can't reach a Windows program or `--print-env`. Tested at the process boundary in `CredentialStorageTests`. (#238) |
| What a profile may do | ✅ | `[env]` cannot set `DYLD_*`, `LD_*`, `WINELOADER`, `WINEDLLPATH*`, `PATH`, `HOME` and the like (`ProfileStore.isAllowedEnvKey`), so a profile can't load native code into Wine. (#123) |
| Generated launchers | ✅ | Every shell word single-quoted, plist values XML-escaped, the name a safe file name (`AppBundle.launcherScript`, `bundleName`). (#122) |
| Self-update (Sparkle 2.10) | ✅, off until keyed | EdDSA-signed zip, checked before extraction (`SUVerifyUpdateBeforeExtraction`); never installs on its own (`SUAllowsAutomaticUpdates` off). Signed feed (`SURequireSignedFeed`) once the key exists. (#125, #128) |
| URL schemes, XPC, sockets | ✅ none | Cellar registers no URL scheme and listens on nothing. The app drives the CLI it carries in its own bundle (`Contents/MacOS/cellar`, preferred over anything on `PATH`) as a child process, so there is no IPC surface another program can reach. |
| Files and logs | ✅ | See the inventory above: `0600`/`0700`, out of backups, redacted at write time. |
| Wine's view of the Mac | ⚠️ open | Drive Z: maps `/`, so Windows programs can browse the whole file system. (#126) |
| App Sandbox | ❌ not feasible | Sandbox restrictions are inherited by child processes, and Wine has to exec unsigned code, share memory with `wineserver` and write arbitrary prefixes. Isolation is done per bottle instead (#126). |
| Hardened runtime, Developer ID, notarization | Accepted risk (deferred) | Kenneth decided on 2026-10-31 not to sign with a Developer ID for now; Cellar is distributed only from the site and GitHub Releases. What this costs: Gatekeeper can't vouch for the publisher, players have to click **Open Anyway** once, the hardened runtime stays off, the CLI re-asks for keychain access after updates, and Sparkle has no Developer ID fallback if the EdDSA key changes. What stands in for it: every release publishes `SHA256SUMS.txt` and a build-provenance attestation, the site shows the DMG's SHA-256 under the Download button, and the FAQ walks through checking it and through Open Anyway on macOS 27 (never via removing the quarantine flag). Updates stay EdDSA-signed. The scripts stay ready (`sign-app.sh`, `notarize.sh`, `make-dmg.sh`); Cellar needs **no** entitlements, and must never get `allow-dyld-environment-variables` or `disable-library-validation`. (#127) |
| Repository + CI | ✅ | CodeQL, dependency review, Scorecard, pinned actions, least-privilege `permissions:`, rulesets on `main` and tags (`docs/RELEASING.md`). |
