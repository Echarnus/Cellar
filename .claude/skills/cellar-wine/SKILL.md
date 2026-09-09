---
name: cellar-wine
description: Best practices for Cellar's translation layer — Wine runners, graphics backends and bottles. Use when editing Runner.swift, Wine.swift, Prefix.swift, the store bottles, or anything that assembles or launches the layer. Covers the four load-bearing launch findings (no /usr/bin/arch, inherit-then-strip the environment, merge WINEDLLOVERRIDES), why WineForge is the default runner and every other one was rejected, bottle hygiene and teardown, and the Rosetta sunset.
---

# Cellar — Wine, runners & bottles

The full guide is [`skills/wine-and-runners.md`](../../../skills/wine-and-runners.md); read it. The
evidence behind every claim is in [`docs/RESEARCH.md`](../../../docs/RESEARCH.md) — rules here,
receipts there. Key rules:

- **Never bundle D3DMetal** (Apple's, user-supplied, grafted at runtime), never commit bottles,
  runners, depots or logs, never circumvent DRM or anti-cheat.
- **Launching Wine — do not regress:** don't wrap it in `/usr/bin/arch -x86_64` (SIP strips `DYLD_*`
  and the runner's dylibs stop resolving); **inherit** the caller's environment then **strip** any
  `WINE*`/`DYLD_*`/`D3DM*`/`MTL_*`/`GST_*`/`GRAPHICS_BACKEND` it carried; **merge**
  `WINEDLLOVERRIDES`, never assign over it (a plain assignment silently drops the backend and the
  game launches on the wrong renderer). A *bare* environment makes PC2 exit silently ~4 s in.
- **Runner default is WineForge** (Wine 11.17 + D3DMetal 3.0). GPTK 7.7 crash-loops the Steam CEF
  helper; Sikarugir 10.0 hits the `gs:[0x20]` fiber bug; stock Wine 11 dropped
  `ntdll.__wine_unix_call` that D3DMetal imports. Add a runner by teaching `RunnerInstall` its
  layout, not by branching at a call site.
- **One game, one bottle.** Prefixes are not forward compatible — changing a bottle's runner is a
  migration, not a config edit. `bottle.toml` is read by a scalar scanner, same constraints as a
  profile ([`cellar-profiles`](../cellar-profiles/SKILL.md)).
- **Tear the layer down with the game:** client, `Agent.exe`, helpers, then `wineserver -k`. A
  surviving `Agent.exe` greys out Install next session.
- **Wine's stderr is exactly the volume that deadlocks `Shell.run`** — use `inheritIO` (see
  [`cellar-swift`](../cellar-swift/SKILL.md)).
- **Verify by a game actually starting**, plus `--print-env` and a clean process table afterwards —
  never by a clean build. Record the hardware and OS in the profile's `notes`.

Before reporting done, run the **cellar-verifier** agent.
