#!/bin/bash
# Fork helper. Builds this checkout, then puts the app in ~/Applications as
# "Relay.app" and signs it there (install.sh is the same for /Applications,
# without the dev build's yellow icon): this folder is in iCloud Drive, whose file
# attributes code signing refuses, so build.sh's own signing step fails here.
#
# Relay has a bundle id of its own (com.chiduong.relay) and a folder of its
# own (~/Library/Application Support/Relay), so it shares nothing with an
# installed Search. What it started with was copied across once (migrate.sh).
set -uo pipefail
cd "$(dirname "$0")"
SEARCH_DEV="${RELAY_DEV:-1}" SEARCH_FEATURE="${1:-mine}" ./build.sh > build-log.txt 2>&1
grep -q 'Build complete' build-log.txt || { tail -20 build-log.txt; echo "build failed" >&2; exit 1; }
set -e
DEST="${RELAY_DEST:-$HOME/Applications}/Relay.app"
PLIST="$DEST/Contents/Info.plist"
mkdir -p "$(dirname "$DEST")"
# One Relay.app on the Mac: two with the same bundle id, and which one a
# link or the Dock opens is anyone's guess. The old ones go to the Trash.
# (RELAY_KEEP=1 leaves them be: release.sh packs a build without installing it.)
for OLD in "$HOME/Applications/Relay.app" "/Applications/Relay.app"; do
  [ "${RELAY_KEEP:-0}" = 1 ] && break
  if [ -d "$OLD" ]; then mv "$OLD" "$HOME/.Trash/Relay $(date +%Y%m%d-%H%M%S)-$RANDOM.app"; fi
done
ditto --norsrc --noextattr --noqtn build/Relay.app "$DEST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.chiduong.relay" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Relay" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Relay" "$PLIST"
# The dev build's "Relay-mine" name, taken off again: this one is Relay.
/usr/libexec/PlistBuddy -c "Delete :LSHasLocalizedDisplayName" "$PLIST" 2>/dev/null || true
find "$DEST/Contents/Resources" -name InfoPlist.strings -delete
xattr -cr "$DEST"
codesign --force --deep --sign - "$DEST"
codesign --verify --strict "$DEST"
echo "installed: $DEST"
