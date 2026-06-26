# Third-Party Licenses & Redistribution Matrix

Cellar orchestrates and (where licenses permit) bundles several open-source components, and
**requires the user to supply** one proprietary Apple component. This document records each
component's license and how Cellar treats it. Verified against upstream `LICENSE` files (2026).

| Component | Purpose | License | Cellar bundles it? | Obligations |
|---|---|---|---|---|
| **Wine** (Gcenx `wine-crossover` builds) | Win32 → macOS API layer | **LGPL-2.1+** | ✅ Yes (planned, Phase 1) | Ship full LGPL text; publish any Wine source **modifications**; preserve ability to relink; no added reverse-engineering restrictions |
| **DXVK** | DirectX 9/10/11 → Vulkan | **zlib/libpng** | ✅ Yes | Don't misrepresent origin; keep notice; mark altered sources |
| **VKD3D-Proton** | DirectX 12 → Vulkan | **LGPL-2.1+** | ✅ Yes | Same LGPL obligations as Wine |
| **MoltenVK** | Vulkan → Metal | **Apache-2.0** | ✅ Yes | Include license; retain notices; **preserve the NOTICE file**; state modifications |
| **FAudio** | XAudio2 reimplementation | **zlib** | ✅ Yes | zlib attribution |
| **DXMT** (`3Shain/dxmt`) | DirectX 11 → Metal | per its repo (verify per release) | ✅ Optional | Per its LICENSE |
| **swift-argument-parser** | CLI parsing | **Apache-2.0** | ✅ Yes (build dep) | Include license; retain NOTICE |
| **Apple D3DMetal / `libd3dshared`** (Game Porting Toolkit `.dmg`) | DirectX 11/12 → Metal | **Proprietary — Apple license** (personal / non-commercial use; redistribution restricted) | ❌ **NO — user-supplied** | Never in this repo or any release. The user downloads Apple's `.dmg` themselves; Cellar copies it into a local cache only |
| **Apple Metal Shader Converter** | DXIL → Metal shaders | Apple (more permissive — redistribution allowed) | Conditionally | Fetched alongside GPTK; cleanest to keep user-supplied too |
| **CrossOver** app/GUI/installer | Commercial Wine front-end | **Proprietary (CodeWeavers)** | ❌ Never | Only CodeWeavers' **public LGPL `winecx` Wine modifications** may be reused — never the GUI/installer/product code |
| **DepotDownloader** (if invoked) | Owned-game depot download | **GPL-2.0** (dep SteamKit2: LGPL-2.1) | Invoked as an external tool | If ever bundled, the combined work must be GPL-compatible |

## The one rule that matters most

**Apple's D3DMetal is never committed to this repository and never shipped in a release artifact.**
It is downloaded by the end user from Apple, under Apple's license, and imported locally via
`cellar gptk import`. This keeps Cellar unambiguously free and legal while still offering the fastest
graphics path. The fully open **DXVK → MoltenVK** path always remains available with no Apple download.

## License of Cellar itself

Cellar's own source is **GPL-3.0** (see [LICENSE](LICENSE)) — one-way compatible with the LGPL-2.1+,
zlib, Apache-2.0, MIT, and BSD components above. When distributing builds that bundle the components
marked "✅", reproduce their license texts and notices (this file plus a `licenses/` folder in release
artifacts) and publish any modifications to the LGPL components.
