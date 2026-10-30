# Licence texts shipped with Cellar

Every Cellar release carries this folder, next to `LICENSE`, `NOTICE` and `THIRD_PARTY_LICENSES.md`:
inside the app at `Cellar.app/Contents/Resources/Legal/`, and in the CLI zip at `share/cellar/legal/`.

| File | Covers |
|---|---|
| [`../LICENSE`](../LICENSE) | Cellar itself — GPL-3.0 |
| [`swift-argument-parser.txt`](swift-argument-parser.txt) | swift-argument-parser, the one third-party library compiled into a Cellar binary |

Only code that is **inside** a Cellar artifact needs its licence here. Wine runners, DepotDownloader
and the storefront clients are downloaded by the player's own copy of Cellar at run time from their
publishers, and carry their own licences with them. See
[`THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md) for the full inventory.
