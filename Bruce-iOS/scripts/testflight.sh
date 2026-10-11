#!/usr/bin/env bash
# Archive Bruce-iOS and upload it to App Store Connect / TestFlight (internal testing only).
#
#   scripts/testflight.sh             archive + export + upload
#   scripts/testflight.sh --no-upload archive + export an .ipa locally (no upload)
#
# Personal values are never committed. They come from the environment or from the git-ignored
# Bruce-iOS/.env (copy .env.example); TEAM_ID falls back to DEVELOPMENT_TEAM in Config/Local.xcconfig.
# Required: TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID. Signing is automatic: -allowProvisioningUpdates plus the
# App Store Connect API key lets xcodebuild create the distribution certificate/profile itself. The key
# file is only passed to xcodebuild, never read here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load KEY=VALUE lines from .env without overriding variables already set in the environment.
ENV_FILE="${ENV_FILE:-$ROOT/.env}"
if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    value="${value%\"}"; value="${value#\"}"
    if [[ -z "${!key:-}" ]]; then export "$key=$value"; fi
  done < "$ENV_FILE"
fi

if [[ -z "${TEAM_ID:-}" && -f "$ROOT/Config/Local.xcconfig" ]]; then
  TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Z0-9]*\).*/\1/p' "$ROOT/Config/Local.xcconfig" | head -n1)"
fi

missing=()
for v in TEAM_ID ASC_KEY_ID ASC_ISSUER_ID; do [[ -n "${!v:-}" ]] || missing+=("$v"); done
if (( ${#missing[@]} )); then
  echo "Missing: ${missing[*]}. Set them in the environment or in $ENV_FILE (see .env.example)." >&2
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-net.dauernheim.bruce}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"      # monotonically increasing per upload
MARKETING_VERSION="${MARKETING_VERSION:-}"                   # empty = keep Config/Base.xcconfig value

DESTINATION=upload
[[ "${1:-}" == "--no-upload" ]] && DESTINATION=export

OUT="$ROOT/build/testflight/$BUILD_NUMBER"
ARCHIVE="$OUT/BruceiOS.xcarchive"
mkdir -p "$OUT"

[[ -f "$ASC_KEY_PATH" ]] || { echo "App Store Connect API key not found: $ASC_KEY_PATH" >&2; exit 1; }

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

OVERRIDES=(DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
           CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
[[ -n "$MARKETING_VERSION" ]] && OVERRIDES+=(MARKETING_VERSION="$MARKETING_VERSION")

echo "==> Archiving $BUNDLE_ID build $BUILD_NUMBER (team $TEAM_ID)"
xcodebuild archive \
  -project "$ROOT/BruceiOS.xcodeproj" -scheme BruceiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  "${AUTH[@]}" "${OVERRIDES[@]}"

EXPORT_OPTIONS="$OUT/ExportOptions.plist"
cp "$ROOT/Config/ExportOptions.plist" "$EXPORT_OPTIONS"
plutil -replace teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
plutil -replace destination -string "$DESTINATION" "$EXPORT_OPTIONS"

echo "==> Exporting (destination: $DESTINATION)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$OUT/export" \
  "${AUTH[@]}"

if [[ "$DESTINATION" == upload ]]; then
  echo "==> Uploaded build $BUILD_NUMBER. It appears in TestFlight after App Store Connect finishes processing."
else
  echo "==> IPA written to $OUT/export (not uploaded)"
fi
