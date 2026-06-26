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
   - Downloading the Windows files of a game you own (in-bottle Windows Steam, or `DepotDownloader` /
     `steamcmd` with the platform forced to Windows) is ownership-gated by Steam itself.
   - Honest framing: under the Steam Subscriber Agreement, content is **"licensed, not sold"** — you
     are licensed to *use the content*, not entitled to the *files*. Third-party depot tools are
     reverse-engineered protocol clients and sit in a **tolerated gray area** for personal use, not an
     affirmatively granted right. The **in-bottle Windows Steam** path uses the real client and avoids
     that gray area — which is why it's the default.

4. **Trademark-safe.** "Cellar" is an original name. Names like Apple, Metal, Game Porting Toolkit,
   Steam, Proton, CrossOver, Planet Coaster, and COBRA are used **descriptively only** (nominative
   use) to state compatibility. No third-party logos. A prominent non-affiliation disclaimer ships in
   [NOTICE](../NOTICE).

5. **No proprietary CrossOver code.** Only CodeWeavers' publicly published **LGPL `winecx` Wine
   modifications** may be reused — never CrossOver's GUI, installer, or product code.

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
