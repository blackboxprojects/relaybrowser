#!/bin/bash
# Fork helper, run once: gives Relay a copy of what Search Mine had. What
# macOS keeps per bundle id (settings, cookies and site data, extension
# storage) and the browser's own folder (tabs, pins, bookmarks, installed
# extensions). Nothing is removed from the source, and nothing already
# there is overwritten. Both browsers must be quit.
set -euo pipefail
OLD=com.chiduong.searchmine
NEW=com.chiduong.relay
if pgrep -f "/Contents/MacOS/(Search|Relay)$" > /dev/null; then echo "a browser is still running" >&2; exit 1; fi
copy() {
  if [ -e "$1" ] && [ ! -e "$2" ]; then ditto "$1" "$2"; echo "copied: $2"; else echo "left alone: $2"; fi
}
copy "$HOME/Library/Application Support/Search" "$HOME/Library/Application Support/Relay"
copy "$HOME/Library/WebKit/$OLD" "$HOME/Library/WebKit/$NEW"
copy "$HOME/Library/HTTPStorages/$OLD" "$HOME/Library/HTTPStorages/$NEW"
copy "$HOME/Library/HTTPStorages/$OLD.binarycookies" "$HOME/Library/HTTPStorages/$NEW.binarycookies"
if defaults read "$NEW" > /dev/null 2>&1; then
  echo "left alone: settings of $NEW"
else
  defaults export "$OLD" - | defaults import "$NEW" -
  echo "copied: settings of $NEW"
fi
