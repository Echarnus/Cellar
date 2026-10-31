# Legal & compliance rules

Cellar is intended to be **free and legal to use and distribute**. These are the project's firm
rules. They are not legal advice, but they encode the conservative, defensible posture established by
verified research into each component's license and the relevant law.

## The five rules

1. **Cellar never bundles Apple's D3DMetal in its own artifacts.** It is never committed to this
   repo and never shipped in a Cellar release. Apple's license grants personal/non-commercial use and
   permits **distribution "solely for non-commercial purposes."** D3DMetal therefore reaches the
   user's machine in one of two ways, both consistent with that grant:
   - **Default:** the player's copy of Cellar downloads a community runner at run time — the
     WineForge Wine build, with D3DMetal taken from **Sikarugir's** wrapper template (the legacy
     `gptk` runner takes it from **Gcenx's** Game Porting Toolkit build instead). Those are
     non-commercial projects redistributing D3DMetal under Apple's non-commercial grant — the same
     model Heroic uses. Cellar fetches it from them; it is not part of Cellar's source or releases.
   - **Spotless (advanced):** the user downloads Apple's own GPTK `.dmg` (free Apple ID) and imports
     it with `cellar gptk import`.
   The fully open **DXVK / DXMT** path is always available as a no-Apple-component alternative for
   titles that don't need D3DMetal.

2. **Never circumvent DRM or anti-cheat.** Planet Coaster 2 ships **Denuvo Anti-tamper** (a DRM layer
   that runs in user space) — *not* Denuvo Anti-Cheat and no kernel anti-cheat. Cellar runs DRM
   **through** the translation layer untouched. We never strip, crack, or bypass it. (Circumventing
   technical protection measures is unlawful under the US DMCA §1201 and EU equivalents.) Titles that
   require defeating kernel anti-cheat are out of scope, not worked around.

3. **Owned games only.** Any game files come exclusively from the user's own authenticated account.
   For Steam and Battle.net that means the storefront's own client, installed in the bottle and
   running unmodified — Cellar issues the same commands a player would click. For GOG it means GOG's
   own API, called with a token the player granted (see *Store authentication* below).
   - Downloading the Windows files of a game you own (in-bottle Windows Steam, or `DepotDownloader` /
     `steamcmd` with the platform forced to Windows) is ownership-gated by Steam itself.
   - Honest framing: under the Steam Subscriber Agreement, content is **"licensed, not sold"** — you
     are licensed to *use the content*, not entitled to the *files*. Third-party depot tools are
     reverse-engineered protocol clients and sit in a **tolerated gray area** for personal use, not an
     affirmatively granted right. The **in-bottle Windows Steam** path uses the real client and avoids
     that gray area — which is why it's the default.

4. **Trademark-safe.** "Cellar" is an original name. Names like Apple, Metal, Game Porting Toolkit,
   Steam, Battle.net, Blizzard, Proton, CrossOver, Planet Coaster, Diablo and COBRA are used
   **descriptively only** (nominative use) to state compatibility. A prominent non-affiliation
   disclaimer ships in [NOTICE](../NOTICE).

   **Store marks.** Cellar labels each game with the storefront it came from, and that label carries a
   small mark. **No logo file is committed, bundled, or downloaded**, which keeps rule 1's "we
   redistribute nobody's proprietary assets" intact. The mark comes from one of two places
   (`Sources/CellarKit/Stores/StoreIcon.swift`):

   - **The store's own installation on this machine** — the `.icns` inside the store's Mac app, the
     icon Wine extracted from the Windows client's `.exe` during setup, or a loose `.ico` the client
     ships. This is the player's own copy of the store's artwork, displayed in place; nothing is
     redistributed, exactly as with Apple's D3DMetal.
   - **A vector shape Cellar draws itself** (`Sources/CellarUI/Marks/`) when the store is
     not installed and there is nothing to point at.

   This matters because every storefront's own brand terms rule out shipping the artwork: Valve's
   guidelines forbid the Steam logo as a prominent feature on non-Valve materials and reserve prior
   approval of anything carrying it; Blizzard's permit their marks only for the fan-site, tournament
   and custom-map activities they enumerate, and only non-commercially; GOG publishes a press kit but
   grants no licence in it. A GPL-3.0 release could not relicense any of it in any case.

   Use is nominative either way: identifying which storefront a game belongs to is the information the
   player needs, and it does not imply endorsement. If a rights-holder ever objected, the fallback is
   one line — swap `StoreMark` for the neutral SF Symbol already named in
   `StoreDescriptor.symbolName`.

5. **No proprietary CrossOver code.** Only CodeWeavers' publicly published **LGPL `winecx` Wine
   modifications** may be reused — never CrossOver's GUI, installer, or product code.

## Store authentication

Cellar signs in to stores *as the player*, and never stores a password. What each flow actually is,
stated plainly, because the three sit in different places:

| Flow | What it is | Standing |
|---|---|---|
| **Steam client** (in the bottle) | the real Windows Steam client, signing in to itself | Valve's own software, unmodified |
| **Steam downloads** (`cellar steam login`) | Steam's own device-authorization flow (`IAuthenticationService/BeginAuthSessionViaQR`) via DepotDownloader | reverse-engineered protocol client — the same **tolerated gray area** as rule 3, which is why the in-bottle client stays the default |
| **GOG** (`cellar gog login`) | OAuth 2.0 authorization-code flow against `auth.gog.com`, then GOG's product/download API | GOG Galaxy's own published endpoints; DRM-free catalogue by GOG's own policy |

Points worth being explicit about:

- **No credential ever reaches Cellar.** Steam's QR flow is approved in the Steam mobile app; GOG's
  sign-in happens on GOG's own page in a `WKWebView` with a non-persistent data store, and Cellar
  reads nothing from that page except the authorization code GOG hands back. No script is injected.
- **Tokens live in the login keychain**, not in a file under Application Support, scoped per store and
  marked `WhenUnlockedThisDeviceOnly` so a refresh token is never carried to another Mac by keychain
  sync or a Time Machine restore (`Sources/CellarKit/Credentials/Keychain.swift`).
- **GOG Galaxy's OAuth client id is used**, because GOG operates no registration portal for
  third-party applications — there is no per-app id to obtain instead. It is public knowledge, ships
  in GOG's own client, and is what every third-party GOG integration authenticates with. Cellar uses
  it only to authenticate the player to GOG and fetch games that player owns.
- **Nothing here circumvents anything.** GOG's catalogue carries no DRM to circumvent; Steam's DRM
  runs untouched inside the bottle exactly as rule 2 requires. Cellar downloads only what the
  authenticated account is entitled to, and the store is the thing enforcing that.
- **None of the three is a vendor-sanctioned public API for launchers.** Valve, Blizzard and GOG each
  publish no such thing. If a rights-holder objected to a flow, the fallback is to remove that store's
  plugin — the store layer is built so that costs one `GameStore` case.

## Epic Games Store: decided, not yet built

Recorded before any code, as issue #39 asks. **Decision: Epic is acceptable only through Epic's own
Windows launcher, installed in the bottle and signed in by the player — the Steam and Battle.net
model. Cellar will not talk to Epic's services with the launcher's credentials.**

The two ways a Mac launcher reaches an Epic library, and why only one fits Cellar's rules:

| Route | What it is | Verdict |
|---|---|---|
| **The Epic Games Launcher in the bottle** | Epic's own unmodified Windows client. The player signs in inside its window; Cellar installs it, keeps it quiet, and asks it to start a game with the same `com.epicgames.launcher://apps/<id>?action=launch` link a desktop shortcut uses. | **Acceptable** — rule 3 exactly as it applies to Steam and Battle.net. Epic's own DRM and Epic Online Services run untouched. |
| **Legendary-style direct API** | A reverse-engineered client that authenticates to Epic's account and download services *as the Epic Games Launcher*, using that launcher's OAuth client id and secret, then downloads and launches games itself. | **Not acceptable for Cellar.** |

Why the second route is a different case from GOG, though both reuse a vendor's client id:

- **Epic offers third parties a real registration path; GOG offers none.** Epic Account Services lets an
  application register its own client and sign players in under its own name. It grants no library or
  download scopes, so a launcher cannot use it — but the fact that a sanctioned path exists means
  presenting as Epic's launcher is a choice to impersonate, not the only way in. For GOG it is the only
  way in, and GOG's catalogue carries no DRM.
- **It is a confidential client's secret, not a public id.** The launcher authenticates with a client
  id *and secret*. Reusing a secret embedded in another company's binary sits further into the gray
  area than rule 3's tolerated depot tools, and Epic's terms forbid accessing its services by means
  other than the interfaces it provides.
- **Many Epic titles carry Epic's own DRM or Easy Anti-Cheat** with a live session to the launcher. A
  client-less route would need to stand in for that session — the line rule 2 draws.

So the build, when a game needs it, mirrors Battle.net rather than GOG:

- `GameStore.epic` with `installsClientInBottle = true`, `authStyle = .inClientWindow`, and
  `canDetectSignIn = false` until Cellar finds a file the launcher writes that says who is signed in
  (it is not known to write one).
- **Ownership is unverifiable**, as with Battle.net: Accounts asks once ("Add"), never claims a sign-in,
  and `StoreLibrary.verdict` withholds Epic's games until it is given.
- Installed games are read from the manifests the launcher writes for every install
  (`ProgramData/Epic/EpicGamesLauncher/Data/Manifests/*.item` in the bottle); Cellar never writes them.
- The store mark follows rule 4: the launcher's own icon from the bottle, or a drawn mark.

Not started until a game the player owns needs it, and verified on a real Mac before any Epic
profile leaves `untested` — the launcher's embedded browser is the part of it most likely to need
work under Wine.

## License hygiene

- Cellar's own code: **GPL-3.0**.
- [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) is the inventory: every component, whether
  Cellar ships it or the player's copy fetches it at run time, and what its licence asks.
- Every release carries `LICENSE`, `NOTICE`, `THIRD_PARTY_LICENSES.md` and [`licenses/`](../licenses/)
  — in `Cellar.app/Contents/Resources/Legal/` and the CLI zip's `share/cellar/legal/`
  (`Scripts/package.sh`), and `LICENSE`/`NOTICE` at the top of the DMG (`Scripts/make-dmg.sh`).
  GPL-3.0 §4 requires the licence text to travel with the binary; the source is the release's tag.
- A component that ends up **inside** a Cellar artifact needs its licence text in `licenses/`, a row
  in the inventory, and a `Credit` (`Sources/CellarKit/Core/Credits.swift`) — the About screen and
  Settings › About read that list. A component fetched at run time needs the row and the `Credit`;
  `CreditsTests` fails when a runner or tool comes from a publisher the credits do not name.
- Cellar carries no modifications to Wine or any other LGPL component. If it ever does, publish them.

## Distributing Cellar

GPL-3.0 lets anyone distribute or even sell Cellar. Apple's D3DMetal terms are narrower, and Cellar's
default runner uses D3DMetal, so:

- **Free downloads (GitHub Releases, the site): fine.** This is how Cellar ships today.
- **Do not sell Cellar, put it behind a paywall, or bundle it into a paid product while its default
  graphics path is D3DMetal**, and never pre-install a runner in an artifact. A commercial edition
  would need the DXVK → MoltenVK path as its default and D3DMetal left as something the player
  imports themselves, or a licence from Apple.
- **Signing and notarising** the app with a Developer ID changes none of this; it is distribution,
  not sale.

## If in doubt

Default to the more conservative path: user-supplied over bundled, in-bottle Steam over depot
dumping, descriptive naming over anything that implies endorsement. When a contribution would touch
any of the above, raise it in the PR.
