# Licence texts shipped with Cellar

Every Cellar release carries this folder, next to `LICENSE`, `NOTICE` and `THIRD_PARTY_LICENSES.md`:
inside the app at `Cellar.app/Contents/Resources/Legal/`, and in the CLI zip at `share/cellar/legal/`.

| File | Covers |
|---|---|
| [`../LICENSE`](../LICENSE) | Cellar itself — GPL-3.0 |
| [`swift-argument-parser.txt`](swift-argument-parser.txt) | swift-argument-parser, compiled into both Cellar binaries |
| [`SDL.txt`](SDL.txt) | SDL 3 and sdl2-compat, shipped as `sdl/libSDL3.dylib` and `sdl/libSDL2-2.0.0.dylib` and loaded by the runner's Wine for controllers and wheel force feedback (zlib) |
| [`Sparkle.txt`](Sparkle.txt) | Sparkle 2, the app's self-updater, shipped as `Cellar.app/Contents/Frameworks/Sparkle.framework` (MIT, plus the bsdiff, sais-lite and ed25519 notices it carries) |

Only code that is **inside** a Cellar artifact needs its licence here. Wine runners, DepotDownloader
and the storefront clients are downloaded by the player's own copy of Cellar at run time from their
publishers, and carry their own licences with them. See
[`THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md) for the full inventory.
