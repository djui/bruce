#!/bin/sh
# One autobook tick for launchd. The access token comes from the login Keychain (preferred) or .env.
# caffeinate keeps the Mac from idle-sleeping while a tick waits for a booking window to open.
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${BRUCE_ACCESS_TOKEN:-}" ]; then
  BRUCE_ACCESS_TOKEN="$(/usr/bin/security find-generic-password -s bruce-autobook -a access-token -w 2>/dev/null || true)"
  [ -n "$BRUCE_ACCESS_TOKEN" ] && export BRUCE_ACCESS_TOKEN
fi
NODE="${NODE:-$(command -v node || echo /opt/homebrew/bin/node)}"
cd "$DIR"
exec /usr/bin/caffeinate -i "$NODE" --env-file-if-exists="$DIR/.env" "$DIR/src/node/cli.ts" tick \
  --config "$DIR/autobook.config.json" --state "$DIR/state/autobook-state.json"
