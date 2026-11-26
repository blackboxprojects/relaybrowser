# Releasing Relay

How a release of Relay is made, how every installed Relay finds it, and what
is still to do before the first one. Written 25 November 2026.

Relay is a fork of [Search](https://github.com/driceroland/Search) (MIT,
Office Commun). Its releases live in
[blackboxprojects/relaybrowser](https://github.com/blackboxprojects/relaybrowser),
which is public.

## Where things stand

| Piece | State |
|---|---|
| Source moved to `Code/github/relaybrowser` | Done. `origin` is `blackboxprojects/relaybrowser`, `upstream` is `driceroland/Search`. Committed locally on `mine`; the source is not pushed. |
| Updater reads Relay's own releases | Done in code, covered by unit tests. The swap from one release to the next has not been watched yet (Phase 2). |
| `release.sh` (build, pack, sign the feed, publish) | All three steps run. |
| Release signing key | Made 25 November 2026. The public half is in `ReleaseKey.swift` (uncommitted). **Not backed up yet.** The Relay in `/Applications` predates it. |
| First release on GitHub | [v1.0.21](https://github.com/blackboxprojects/relaybrowser/releases/tag/v1.0.21), 25 November 2026, build 202611251801. Binaries only: its tag sits on the repository's initial commit. The feed and ZIP GitHub serves were downloaded and checked against the key and the hash. |

## How an update reaches a Mac

1. Each Relay asks GitHub for the latest release's `appcast.json` at launch
   and every hour
   (`https://github.com/blackboxprojects/relaybrowser/releases/latest/download/appcast.json`).
2. The file is `{"signed": …, "signature": …}`. Relay opens it only if the
   Ed25519 key it was built with signed it (`ReleaseFeed.swift`,
   `ReleaseKey.swift`).
3. If the feed's build number is higher than the running one, and the Mac's
   macOS is new enough, Relay downloads the ZIP the feed names. The address
   must be among this repository's releases on github.com.
4. The ZIP's SHA-256 must be the one in the signed feed. The app inside must
   have Relay's bundle id, a higher build number, and a code signature that
   holds up.
5. The new bundle is renamed into place beside the old one. Nothing
   relaunches on its own: the window shows "Update ready" with Restart, and
   the new build runs at the next launch.

Settings › About › "Install updates on its own" is on unless switched off.
Off, Relay says a version is out and waits for Install Update in the Relay
menu. If the swap can't be done (the folder isn't writable, say), the menu
offers Download Update, which opens the release's page.

Data is never touched: `~/Library/Application Support/Relay`, the settings
and the keychain stay as they are.

### Why a key of its own

Search trusts an update because Office Commun's Developer ID signed it.
Relay is signed ad hoc, which proves nothing about who built it. So the feed
is signed with a key only the release Mac holds, and the feed vouches for
one ZIP by its hash. An attacker needs both the private key and write access
to the repository's releases to push a build.

## One-time setup

1. **Make the key.** Done; kept here for a new Mac or a new fork.

   ```bash
   ./release.sh key
   ```

   The private half goes into the login keychain as "Relay release key".
   The public half is written into `Sources/Relay/ReleaseKey.swift`; commit
   that file.

2. **Back the key up.** Keychain Access › login › "Relay release key" › show
   password, into a password manager. If it is lost, no installed Relay can
   ever be updated again: each would need a new build installed by hand.
   The script refuses to make a second key over the first for this reason.

3. **Install a build that carries the key** (`./install.sh`). The Relay in
   `/Applications` today was built without one and will never update itself.

## Making a release

1. Merge what is going out, run `swift test`.
2. Raise `VERSION`. A tag is used once; the script names it `v<VERSION>`.
3. In `CHANGELOG.md`, give the Unreleased section its number and date. Put
   its gist as the first paragraph of `NOTES.md`: that paragraph is the line
   Settings shows under the new version, and the release's text on GitHub.
4. Commit, and push if the source is to be on GitHub (see Decisions).
5. Try the package without publishing:

   ```bash
   ./release.sh
   ```

   It builds a release build outside iCloud Drive, leaves `/Applications`
   alone, and writes `build/release/Relay-arm64.zip` and
   `build/release/appcast.json`.
6. Publish:

   ```bash
   ./release.sh publish
   ```

   It refuses with uncommitted changes, then creates GitHub release
   `v<VERSION>` with both files. Within the hour, every Relay with automatic
   updates on has the new build in place.

`RELAY_PRERELEASE=1 ./release.sh publish` marks the release a pre-release.
GitHub's "latest" skips those, so no Relay is offered it.

### Checking a release

- `swift Installer/release-key.swift check build/release/appcast.json <public key>`
  prints what the feed says if the key signed it.
- On a Mac running the previous release: Relay › Check for Updates…, then
  the foot of the window says the new version is downloading, then ready.
  After Restart, Settings › About shows the new version.

### Taking a release back

A Relay never goes down a build. To stop a bad release spreading, mark it a
pre-release (or delete it) on GitHub so "latest" falls back to the one
before, then publish a fixed build with a higher number. Macs that already
took the bad one get the fix as a normal update.

## Plan

**Phase 1: first self-updating release.** Done: v1.0.21. Still open from it: back up the key, and the items under Decisions.

**Phase 2: prove the loop.**
Publish a second release with a trivial change. Confirm the first one finds
it, swaps it in, and comes back as the new build after Restart. This is the
only end-to-end test of the ad-hoc swap; nothing before it exercises the
real feed, the real download or the rename in `/Applications`.

**Phase 3: releases for other people (only if Relay is shared).**
See "Ad-hoc signing" below; a Developer ID is the real fix.

**Phase 4: releases from GitHub Actions (optional).**
A macOS runner builds on a tag, with the key as the `RELAY_RELEASE_KEY`
secret (the signing tool already reads it). Worth it once releases are
frequent; it also moves the private key off one Mac, which is a trade.

## Decisions to make

1. **Source in the release repository, or binaries only.** The local repo
   carries all of Search's history (1,473 commits) on branch `mine`.
   `origin/main` on GitHub holds one unrelated "Initial commit". Either push
   `mine` as the new `main` (a force push over that one commit), or keep the
   GitHub repository for releases alone and the source local. `release.sh`
   works both ways: it tags the pushed commit when there is one.
2. **Version numbers.** `VERSION` is Search's (1.0.20) and moves when
   upstream is merged. Relay needs numbers that don't collide with it:
   continue from 1.0.21 and accept the two drift apart, or start Relay's own
   line (2.0.0). Updates compare build numbers only, so either works.
3. **What a public repository shows.** `README.md`, `SECURITY.md` and
   `CONTRIBUTING.md` are still Search's: they name Office Commun, link
   searchbrowser.app downloads and a Homebrew cask that install Search, not
   Relay. Rewrite them before pushing. Keep `LICENSE` and
   `THIRD_PARTY_NOTICES.md` as they are (MIT requires the notice).
4. **Upstream services Relay still calls.** Send Feedback drafts mail to
   hello@searchbrowser.app; the beta and news sign-ups post to
   searchbrowser.app; AI sign-in returns through officecommun.com. Fine for
   a personal build, wrong for one given to others.
5. **Intel.** Nothing here builds an Intel release unless `release.sh` is
   run on an Intel Mac. Decide whether it matters.

## Risks

- **Ad-hoc signing.** Updates work, but each new build is a different app
  to macOS: keychain "Always Allow" answers and privacy permissions (camera,
  microphone, screen recording) can be asked again after an update. A copy
  downloaded from the release page in a browser is quarantined, and
  Gatekeeper will refuse to open it without System Settings › Privacy &
  Security › Open Anyway. A Developer ID certificate and notarisation
  (Apple Developer Program) remove all three; `build.sh` already knows how
  to use one.
- **The key.** Lost: no more updates for installed copies. Leaked: rotate by
  shipping a build with a new public key while the old key still works.
- **The bundle id** (`com.chiduong.relay`) is checked on every update.
  Changing it later strands every installed copy and its data.
- **GitHub as the only host.** If the repository is renamed, made private or
  removed, updates stop silently. A rename needs a release that carries the
  new address first.

## Files

| File | What it does |
|---|---|
| `release.sh` (build, pack, sign the feed, publish) | All three steps run. |
| `Installer/release-key.swift` | Makes the key, signs and checks the feed |
| `Sources/Relay/ReleaseFeed.swift` | Feed address, signature check, which addresses are allowed |
| `Sources/Relay/ReleaseKey.swift` | The public key (empty until `./release.sh key`) |
| `Sources/Relay/Updater.swift` | Check, download, verify, swap (Search's, with the fork's changes marked "Fork:") |
| `Tests/SearchTests/ReleaseFeedTests.swift` | Signature and address rules |
| `mine.sh`, `install.sh` | Local build and install; `RELAY_KEEP=1` builds without replacing the installed app |
