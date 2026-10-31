# Cellar's patches to SDL

`Scripts/build-sdl.sh` builds SDL 3 from its pinned release tarball and applies every `*.patch` in
this folder to it, in name order, before building. A patch here is how Cellar adds a wheel driver
SDL does not have yet.

| Patch | What it adds |
|---|---|
| `0001-cellar-fanatec-force-feedback.patch` | Force feedback for Fanatec bases in PC mode (CSL DD, GT DD Pro, ClubSport DD, Podium DD1/DD2, CSL Elite, ClubSport V2/V2.5, CSR Elite, Porsche 911). `src/haptic/darwin/SDL_cellar_fanatec.{c,h}` hold the engine; `SDL_syshaptic.c` hands a Fanatec joystick to it instead of ForceFeedback.framework. GPL-2.0-or-later, after [hid-fanatecff](https://github.com/gotzl/hid-fanatecff). |
| `0002-cellar-thrustmaster-force-feedback.patch` | Force feedback for Thrustmaster's T300 family (T300 RS, T300 Ferrari Edition, TX, T248, TS-XW, TS-PC). `SDL_cellar_thrustmaster.{c,h}` hold the engine: effects are uploaded to the wheel's 16 slots and started, changed and stopped by id, queued and sent every 8 ms. `SDL_syshaptic.c` hands such a wheel to it, and switches a T300 that is still the generic "Thrustmaster FFB Wheel" (0xb65d) into its own mode with two USB vendor requests. GPL-2.0-or-later, after [hid-tmff2](https://github.com/Kimplul/hid-tmff2). |

`tests/` holds each driver's unit tests. They build against the patched source and the SDL just
built, with a fake device that records every command, and `build-sdl.sh` runs them on both slices,
so CI runs them on every PR. On Linux they run the same way against any SDL 3 (`-DCELLAR_FFB_STANDALONE`).

Switches, read from the game's environment (they pass through `cellar launch`):

- `CELLAR_FFB_MAX_PERCENT` — the strength cap, 1–100: default 50 for Fanatec, 100 for Thrustmaster
  (applied through the wheel's own gain). Cellar sets it at launch from
  Settings › General › Racing wheels (`CellarSDL.strengthEnvironment`), together with SDL's own
  `SDL_HAPTIC_LG4FF_GAIN` for Logitech wheels; a value typed on the command line wins.
- `CELLAR_FFB_DISABLE=1` — leave Fanatec and Thrustmaster wheels to the runner's path: steering only,
  no force feedback, and no Thrustmaster mode switch.

Rules, because this library runs inside every game's Wine process:

- One driver or fix per patch, named `NNNN-what-it-does.patch`, applying with `patch -p1` to the
  SDL source root.
- zlib §2: altered sources must say so. Each new or changed file carries a line naming Cellar and
  the change.
- Code ported from a GPL driver (Linux `hid-*`) keeps that driver's licence on the file it lands in,
  and `THIRD_PARTY_LICENSES.md` says so before the patch ships.
- Force feedback is a motor: a driver caps its output (`CELLAR_FFB_MAX_PERCENT`) and stops every
  effect when the device closes.
