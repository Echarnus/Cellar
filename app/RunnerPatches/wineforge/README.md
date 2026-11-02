# WineForge patches

Fixes Cellar applies to WineForge's own source, built by `app/Scripts/build-wineserver.sh` and the
*Wineserver* workflow. Each patch is against the exact WineForge tag pinned in that script, and is
dropped once WineForge ships the fix.

| Patch | What it fixes |
|---|---|
| `0001-server-run-user-apcs-before-objects-in-alertable-waits.patch` | Planet Coaster 2's Frontier Workshop and Franchise never load (#23). Frontier's `KeplerAPI.dll` writes its cache with `WriteFileEx` on an overlapped file and then waits, alertably, on the file handle until the completion routine runs. Windows runs a queued user APC before it looks at the objects of an alertable wait; Wine checks the objects first, and a regular file handle is always signalled, so the routine never runs and Frontier's network thread hangs forever. Wine's own `kernel32/tests/file.c` marks this as `todo_wine`. |

Wine is LGPL-2.1-or-later; WineForge's source is at <https://github.com/Alien4042x/WineForge>, and the
patch here is the complete change, so a binary built from it is reproducible from this repository.
