#!/bin/bash
# Fork helper. A release of Relay: the app in a ZIP and the signed feed that
# names it, as assets of a GitHub release in blackboxprojects/relaybrowser.
# Every Relay out there reads the latest release's feed each hour and, if it
# names a newer build, fetches the ZIP, checks it and puts it in place
# (Sources/Relay/Updater.swift, ReleaseFeed.swift). RELEASING.md is the whole
# procedure.
#
#   ./release.sh key       once: makes the signing key (private half into the
#                          login keychain, public half into ReleaseKey.swift)
#   ./release.sh           builds and packs into build/release/, publishes
#                          nothing
#   ./release.sh publish   the same, then puts both files on GitHub as
#                          release v<VERSION> (RELAY_TAG names another tag;
#                          RELAY_PRERELEASE=1 marks it one, which no Relay is
#                          offered)
#
# VERSION names the release, and a tag is used once: raise VERSION first.
# What decides "newer" is the build number, the minute it was built.
# On an Intel Mac the same commands make that chip's files (Relay-x86_64.zip,
# appcast-intel.json) and add them to the release if it is already there.
set -euo pipefail
cd "$(dirname "$0")"

REPO="blackboxprojects/relaybrowser"
KEY=(swift Installer/release-key.swift)
STEP="${1:-pack}"
case "$STEP" in
  key)
    "${KEY[@]}" new Sources/Relay/ReleaseKey.swift
    echo "made: the release key. Its public half is in Sources/Relay/ReleaseKey.swift — commit it."
    echo "The private half is in the login keychain as “Relay release key”. Without it no Relay"
    echo "that carries this public half can ever be updated: keep a copy somewhere safe."
    exit 0 ;;
  pack|publish) ;;
  *) echo "usage: ./release.sh [key|publish]" >&2; exit 1 ;;
esac

PUBLIC="$(sed -n 's/.*publicKey = "\(.*\)".*/\1/p' Sources/Relay/ReleaseKey.swift)"
[ -n "$PUBLIC" ] || { echo "no release key yet — ./release.sh key makes one" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="${RELAY_TAG:-v$VERSION}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) FEED="appcast.json" ;;
  x86_64) FEED="appcast-intel.json" ;;
  *) echo "no release for a $ARCH Mac" >&2; exit 1 ;;
esac
ZIP="Relay-$ARCH.zip"

if [ "$STEP" = "publish" ]; then
  command -v gh >/dev/null || { echo "publishing needs gh (brew install gh)" >&2; exit 1; }
  # What is released is what is committed, so the tag says what the ZIP holds.
  [ -z "$(git status --porcelain)" ] || [ "${RELAY_DIRTY:-0}" = 1 ] \
    || { echo "uncommitted changes — commit them first (RELAY_DIRTY=1 to release anyway)" >&2; exit 1; }
fi

# Built here, installed nowhere: into a folder outside iCloud Drive, where
# mine.sh can sign it, and the Relay in /Applications is left alone.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
RELAY_DEV=0 RELAY_DEST="$STAGE" RELAY_KEEP=1 ./mine.sh
APP="$STAGE/Relay.app"
PLIST="$APP/Contents/Info.plist"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$PLIST")"
MINIMUM="$(plutil -extract LSMinimumSystemVersion raw -o - "$PLIST")"
[ "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" = "$VERSION" ] \
  || { echo "the app built isn't $VERSION" >&2; exit 1; }

ditto -c -k --keepParent "$APP" "$STAGE/$ZIP"
# Opened the way the updater opens it, the signature has to hold up still.
ditto -x -k "$STAGE/$ZIP" "$STAGE/check"
codesign --verify --strict --deep "$STAGE/check/Relay.app"
SHA="$(shasum -a 256 "$STAGE/$ZIP" | cut -d' ' -f1)"

OUT="build/release"
mkdir -p "$OUT"
cp "$STAGE/$ZIP" "$OUT/$ZIP"
# The first paragraph of NOTES.md is the line under the version in Settings.
NOTES=""
[ -f NOTES.md ] && NOTES="$(awk 'NF { printf "%s%s", (n++ ? " " : ""), $0; next } n { exit }' NOTES.md)"
"${KEY[@]}" feed "$OUT/$FEED" expect="$PUBLIC" \
  version="$VERSION" build="$BUILD" sha256="$SHA" minimumSystemVersion="$MINIMUM" notes="$NOTES" \
  url="https://github.com/$REPO/releases/download/$TAG/$ZIP" \
  dmg="https://github.com/$REPO/releases/tag/$TAG"
"${KEY[@]}" check "$OUT/$FEED" "$PUBLIC" >/dev/null
echo "packed: $OUT/$ZIP and $OUT/$FEED ($VERSION, $ARCH, build $BUILD)"
[ "$STEP" = "publish" ] || { echo "./release.sh publish puts them on GitHub as $TAG"; exit 0; }

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  # The other chip's files, added to a release that is already there. The
  # same chip twice is refused by GitHub: a tag's files never change under
  # the Relays that have already read them.
  gh release upload "$TAG" "$OUT/$ZIP" "$OUT/$FEED" --repo "$REPO"
else
  EXTRA=()
  # Tagged at this commit when GitHub has it; a release of binaries alone
  # otherwise, tagged wherever the default branch is.
  if git branch -r --contains HEAD 2>/dev/null | grep -q '^ *origin/'; then
    EXTRA+=(--target "$(git rev-parse HEAD)")
  else
    echo "note: this commit isn't on GitHub — the tag goes on the default branch, not on this source" >&2
  fi
  [ "${RELAY_PRERELEASE:-0}" = 1 ] && EXTRA+=(--prerelease)
  gh release create "$TAG" "$OUT/$ZIP" "$OUT/$FEED" --repo "$REPO" \
    --title "Relay $VERSION" --notes "${NOTES:-Relay $VERSION}" ${EXTRA[@]+"${EXTRA[@]}"}
fi
echo "published: https://github.com/$REPO/releases/tag/$TAG"
