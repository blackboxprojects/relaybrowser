# Relay

A small, fast web browser for the Mac with containers built in. Relay is a
fork of [Search](https://github.com/driceroland/Search) by Office Commun.

**[Download Relay for macOS →](https://github.com/blackboxprojects/relaybrowser/releases/latest/download/Relay-arm64.zip)**
· Apple silicon · macOS 14 or later · free

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-support-yellow?logo=buymeacoffee)](https://www.buymeacoffee.com/blackboxlabs)

## Install

1. Download [Relay-arm64.zip](https://github.com/blackboxprojects/relaybrowser/releases/latest/download/Relay-arm64.zip)
   and open it. It unpacks to `Relay.app`.
2. Drag `Relay.app` into your Applications folder.
3. Open it. Relay is not signed with an Apple Developer ID, so the first
   time macOS will refuse. Either:
   - open System Settings › Privacy & Security, scroll to the message about
     Relay and press **Open Anyway**, or
   - run this once in Terminal:

     ```bash
     xattr -dr com.apple.quarantine /Applications/Relay.app
     ```

After that Relay keeps itself up to date. It reads this repository's latest
release each hour, and a newer build is downloaded, checked against Relay's
signing key and put in place for the next launch. Settings › About ›
"Install updates on its own" turns that off; Relay then tells you a version
is out and waits for Install Update in the Relay menu.

Every version is on the [releases page](https://github.com/blackboxprojects/relaybrowser/releases).
There is no Intel build yet.

## What Relay adds to Search

- **Containers.** A tab can live in a container with sign-ins of its own,
  apart from every other container's: two accounts on the same site, side
  by side. The crate button in the toolbar opens a tab in a container, moves
  the current tab into one, or makes a temporary one. "Always open this site
  here" sends a site to its container every time.
- **Container settings.** Names, colours, site rules, and a space for each
  container to open in.
- **Private windows** that keep nothing, and new windows that open blank.
- **An address bar that can show only the site** until you click it.
- **Slimmer margins** beside the tabs.

Everything else is Search: tabs down the side, spaces, pins, split view,
reading mode, an ad blocker, Chrome extensions, and passwords in your Mac's
keychain. It runs on WebKit, the engine already in every Mac.

## Build from source

With Xcode's command line tools installed:

```bash
git clone https://github.com/blackboxprojects/relaybrowser.git
```

```bash
cd relaybrowser && ./install.sh
```

`./install.sh` builds a release build and puts `Relay.app` in
`/Applications`. `swift test` runs the tests. [RELEASING.md](RELEASING.md)
is how a release is made.

## Support

If Relay is useful to you, you can
[buy me a coffee](https://www.buymeacoffee.com/blackboxlabs).

## Licence

MIT, as Search is. See [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Search is the work of
[Office Commun](https://officecommun.com); Relay is not affiliated with them.
