#!/bin/bash
# Fork helper. A copy of the installed Relay for the bench and Tests/*.py to
# drive, outside iCloud Drive (where signing fails) and under a bundle id of
# its own, so its WebKit stores and its place in the Dock are never the real
# Relay's. Prints the copy's path: RELAY_PROBE_APP="$(./probe.sh)" python3 Tests/….
#
#   ./probe.sh                 copy /Applications/Relay.app
#   ./probe.sh PATH/Relay.app  copy another build
#
# A release build no longer carries the bench: install one that does first,
# with RELAY_BENCH=1 ./install.sh, or the probe has no socket to drive.
set -euo pipefail
FROM="${1:-/Applications/Relay.app}"
DEST="$HOME/Library/Caches/relay-probe/Relay.app"
[ -d "$FROM" ] || { echo "no app at $FROM (run ./install.sh first)" >&2; exit 1; }
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
ditto --norsrc --noextattr --noqtn "$FROM" "$DEST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.chiduong.relay.probe" "$DEST/Contents/Info.plist"
xattr -cr "$DEST"
codesign --force --deep --sign - "$DEST" 2>/dev/null
codesign --verify --strict "$DEST"
echo "$DEST"
