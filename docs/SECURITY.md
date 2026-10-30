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
| Steam refresh token | DepotDownloader's `account.config` (usually `~/Library/Application Support/IsolatedStorage/…`) | `0600`, excluded from backups after every DepotDownloader run (`DepotTool.protectStoredSessions`); Cellar's own folders around it `0700`. |
| Steam refresh token, DPAPI-wrapped | Each Steam bottle's `local.vdf` (`ConnectCache`) | `0600`, excluded from backups. The blob is recoverable by anyone holding the file — it is Wine's DPAPI — so it is treated as the token itself and taken back out on sign-out and reset. |
| Steam account name + dates | `shared/steam-account.json` | `0600` (`PrivateFiles.write`). Not a secret, but it says whose library this is. |
| GOG username | `shared/gog-account` | `0600`. One file both binaries read, so the app never fetches the name with the token. |
| Battle.net | — | Cellar holds nothing: Blizzard's client keeps its own session in the bottle. |

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
- **Tests prove it.** `Tests/CellarKitTests/CredentialStorageTests.swift` feeds real-shaped leaks
  through each path; `Tests/CellarIntegrationTests/KeychainTests.swift` round-trips the real
  keychain under a throwaway service. A change that adds a place a credential can go adds a row
  above and a test there.

## Known limits, and what lifts them

- **The Steam token is still in DepotDownloader's file between runs.** Moving it into the keychain
  means sealing and restoring the file around every DepotDownloader process, including concurrent
  ownership checks from the app and the CLI — tracked as its own issue.
- **The app and the CLI do not share one keychain item.** On the login keychain an item trusts the
  binary that created it; a true shared item needs the data-protection keychain and a
  `keychain-access-groups` entitlement on both, signed with one Team ID. Until the Developer ID
  exists, the CLI is the only reader of secrets and the app only asks whether one exists.
