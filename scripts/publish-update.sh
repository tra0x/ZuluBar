#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH="${1:?Usage: scripts/publish-update.sh <zip-path> [notes]}"
NOTES="${2:-}"

: "${R2_BUCKET:?R2_BUCKET must be set}"
: "${SPARKLE_SIGN:?SPARKLE_SIGN must be set}"
: "${APP_PATH:?APP_PATH must be set}"

# Read version info directly from the built app
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST")
ARTIFACT_FILENAME="${UPDATE_ARTIFACT_FILENAME:-ZuluBar-${VERSION}.zip}"
ARTIFACT_OBJECT_KEY="${UPDATE_ARTIFACT_OBJECT_KEY:-updates/${ARTIFACT_FILENAME}}"
PUBLISH_DATE="${UPDATE_PUB_DATE:-$(date -u "+%Y-%m-%dT%H:%M:%SZ")}"
VARS_FILE="${UPDATE_VARS_FILE:-dist/zulubar-site-release-vars.env}"

echo "→ Publishing ZuluBar $VERSION (build $BUILD)..."

echo "→ Signing with Sparkle Ed25519..."
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    SIGN_OUTPUT=$(echo "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_SIGN" --ed-key-file - "$ZIP_PATH")
else
    SIGN_OUTPUT=$("$SPARKLE_SIGN" "$ZIP_PATH")
fi

SIG=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

[ -n "$SIG" ]    || { echo "Error: failed to extract Ed25519 signature from sign_update output"; exit 1; }
[ -n "$LENGTH" ] || { echo "Error: failed to extract length from sign_update output"; exit 1; }

echo "  Signature: ${SIG:0:20}..."
echo "  Length:    $LENGTH bytes"

echo "→ Uploading ${ARTIFACT_OBJECT_KEY} to private R2..."
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "  Wrangler auth: CLOUDFLARE_API_TOKEN"
else
    echo "  Wrangler auth: local Wrangler login"
fi

wrangler r2 object put "$R2_BUCKET/${ARTIFACT_OBJECT_KEY}" \
    --remote \
    --file "$ZIP_PATH" \
    --content-type "application/zip"

mkdir -p "$(dirname "$VARS_FILE")"
cat > "$VARS_FILE" <<EOF
# Apply these values to the deployment site's production Worker config
# so https://zulubar.app/appcast.xml serves this release.
UPDATE_ARTIFACT_OBJECT_KEY=${ARTIFACT_OBJECT_KEY}
UPDATE_ARTIFACT_FILENAME=${ARTIFACT_FILENAME}
UPDATE_ARTIFACT_LENGTH=${LENGTH}
UPDATE_ARTIFACT_SIGNATURE=${SIG}
UPDATE_VERSION=${BUILD}
UPDATE_SHORT_VERSION=${VERSION}
UPDATE_PUB_DATE=${PUBLISH_DATE}
EOF

echo ""
echo "✓ Published ZuluBar $VERSION (build $BUILD)"
echo "  R2 object: ${R2_BUCKET}/${ARTIFACT_OBJECT_KEY}"
echo "  Appcast:   https://zulubar.app/appcast.xml?key=<customer-key>"
echo "  Vars:      ${VARS_FILE}"
if [ -n "$NOTES" ]; then
    echo "  Notes:     $NOTES"
fi
