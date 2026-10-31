# Security policy

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through
[GitHub's advisory form](https://github.com/Echarnus/Cellar/security/advisories/new). You'll get a
reply within a week, and a fix or a plan within 30 days. You'll be credited in the advisory and the
release notes unless you'd rather not be.

Useful to include: the Cellar version (`cellar --version`), your macOS version, what an attacker
could do, and the steps to reproduce it.

## What's in scope

- The Cellar app, the `cellar` CLI and the release downloads.
- How Cellar stores store credentials (the Keychain) and what it writes into a bottle.
- The update feed and the release workflow.

Wine, the runners, DXVK, MoltenVK, D3DMetal, the store clients and the games themselves are other
projects' software: report those upstream. If Cellar makes one of their issues worse, that part is
in scope.

## Supported versions

Only the latest release receives fixes.

## Verifying a download

Every release lists the SHA-256 of each download in `SHA256SUMS.txt`, and each download carries a
build provenance attestation you can check with the GitHub CLI:

```sh
gh attestation verify Cellar.dmg --repo Echarnus/Cellar
```
