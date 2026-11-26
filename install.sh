#!/bin/bash
# Fork helper. Relay as an app to keep: a release build with its own icon
# (not the dev build's yellow one), in /Applications. Everything else is
# mine.sh, which says why the signing happens there and not here.
#
#   ./install.sh               into /Applications
#   RELAY_DEST=~/Applications ./install.sh
set -euo pipefail
cd "$(dirname "$0")"
RELAY_DEV=0 RELAY_DEST="${RELAY_DEST:-/Applications}" exec ./mine.sh
