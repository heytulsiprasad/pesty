#!/usr/bin/env bash
# Sign a locally built Pesty with a real signing identity and install it.
#
# Why this exists: an ad-hoc signature identifies the app by cdhash, which
# changes on every rebuild, so macOS silently revokes the Accessibility grant
# each time and Return stops pasting. Signing with a Developer ID gives a
# designated requirement based on bundle id + team, which survives rebuilds.
#
# Not notarized — unnecessary for a local install, since Gatekeeper only
# assesses apps carrying a quarantine flag.
#
#   ./scripts/build_app.sh && ./scripts/sign_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="packaging/Pesty.app"
DEST="/Applications/Pesty.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"

[ -d "$APP" ] || { echo "Missing $APP — run ./scripts/build_app.sh first"; exit 1; }
[ -n "$IDENTITY" ] || { echo "No Developer ID identity found. Set SIGN_IDENTITY."; exit 1; }

echo "==> Signing as: $IDENTITY"
for target in "$APP/Contents/MacOS/Pesty" "$APP"; do
    codesign --force --options runtime --timestamp \
        --entitlements packaging/Pesty.entitlements \
        --sign "$IDENTITY" "$target"
done

codesign --verify --strict "$APP"
echo "==> Designated requirement:"
codesign -d -r- "$APP" 2>&1 | grep '^designated' || true

if [ "${INSTALL:-1}" = "1" ]; then
    osascript -e 'quit app "Pesty"' 2>/dev/null || true
    pkill -x Pesty 2>/dev/null || true
    sleep 1
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open -a "$DEST"
    echo "==> Installed and relaunched $DEST"
fi
