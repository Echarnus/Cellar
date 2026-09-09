# Legal & compliance rules

Cellar is intended to be **free and legal to use and distribute**. These are the project's firm
rules. They are not legal advice, but they encode the conservative, defensible posture established by
verified research into each component's license and the relevant law.

## The five rules

1. **Cellar never bundles Apple's D3DMetal in its own artifacts.** It is never committed to this
   repo and never shipped in a Cellar release. Apple's license grants personal/non-commercial use and
   permits **distribution "solely for non-commercial purposes."** D3DMetal therefore reaches the
   user's machine in one of two ways, both consistent with that grant:
   - **Default (minimal setup):** `cellar runner install gptk` downloads the **Gcenx Game Porting
     Toolkit** Wine build at runtime. Gcenx is a non-commercial project redistributing D3DMetal under
     Apple's non-commercial grant — the same model Heroic uses. Cellar fetches it; it is not part of
     Cellar's source or releases.
   - **Spotless (advanced):** the user downloads Apple's own GPTK `.dmg` (free Apple ID) and imports
     it with `cellar gptk import` (Phase 2).
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
   (`Sources/CellarKit/StoreIcon.swift`):

   - **The store's own installation on this machine** — the `.icns` inside the store's Mac app, the
     icon Wine extracted from the Windows client's `.exe` during setup, or a loose `.ico` the client
     ships. This is the player's own copy of the store's artwork, displayed in place; nothing is
     redistributed, exactly as with Apple's D3DMetal.
   - **A vector shape Cellar draws itself** (`Sources/CellarApp/StoreMark.swift`) when the store is
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
  sync or a Time Machine restore (`Sources/CellarKit/Keychain.swift`).
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

## License hygiene

- Cellar's own code: **GPL-3.0**.
- Every bundled component keeps its own license; texts and notices are reproduced in
  [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) and in a `licenses/` folder in release builds.
- Publish any modifications Cellar makes to LGPL components (Wine, VKD3D-Proton).
- Preserve MoltenVK's `NOTICE` and the zlib origin notices.

## If in doubt

Default to the more conservative path: user-supplied over bundled, in-bottle Steam over depot
dumping, descriptive naming over anything that implies endorsement. When a contribution would touch
any of the above, raise it in the PR.
