# Cellar's patches to SDL

`Scripts/build-sdl.sh` builds SDL 3 from its pinned release tarball and applies every `*.patch` in
this folder to it, in name order, before building. A patch here is how Cellar adds a wheel driver
SDL does not have yet (a Fanatec force-feedback driver is the next one).

Rules, because this library runs inside every game's Wine process:

- One driver or fix per patch, named `NNNN-what-it-does.patch`, applying with `patch -p1` to the
  SDL source root.
- zlib §2: altered sources must say so. Each new or changed file carries a line naming Cellar and
  the change.
- Code ported from a GPL driver (Linux `hid-*`) keeps that driver's licence on the file it lands in,
  and `THIRD_PARTY_LICENSES.md` says so before the patch ships.
- Force feedback is a motor: a driver caps its output (`CELLAR_FFB_MAX_PERCENT`) and stops every
  effect when the device closes.
