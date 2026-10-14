#!/bin/sh
# Installs (or reinstalls) the launchd agent for the current user and starts it.
# Uninstall: launchctl bootout gui/$(id -u)/net.dauernheim.bruce.autobook && rm ~/Library/LaunchAgents/net.dauernheim.bruce.autobook.plist
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL=net.dauernheim.bruce.autobook
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
NODE="$(command -v node)" || { echo "node not found in PATH (need Node >= 22.18)" >&2; exit 1; }
[ -f "$DIR/autobook.config.json" ] || { echo "missing $DIR/autobook.config.json (copy autobook.config.example.json)" >&2; exit 1; }
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
sed -e "s|__AUTOBOOK_DIR__|$DIR|g" -e "s|__NODE__|$NODE|g" -e "s|__HOME__|$HOME|g" \
  "$DIR/deploy/$LABEL.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $PLIST; log: ~/Library/Logs/bruce-autobook.log"
