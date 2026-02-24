#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: scripts/publish-update.sh <version> <zip-path> [notes]}"
ZIP_PATH="${2:?Usage: scripts/publish-update.sh <version> <zip-path> [notes]}"
NOTES="${3:-}"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"
: "${R2_BUCKET:?R2_BUCKET must be set}"
: "${SPARKLE_SIGN:?SPARKLE_SIGN must be set}"

echo "→ Signing with Sparkle Ed25519..."
# In CI: set SPARKLE_ED_PRIVATE_KEY and this pipes it to sign_update via --ed-key-file -
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

echo "→ Updating appcast.xml..."
DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
URL="https://updates.zulubar.app/ZuluBar-${VERSION}.zip"
python3 scripts/add-appcast-entry.py "$VERSION" "$SIG" "$LENGTH" "$DATE" "$URL" "$NOTES"

echo "→ Uploading ZuluBar-${VERSION}.zip to R2..."
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
    wrangler r2 object put "$R2_BUCKET/ZuluBar-${VERSION}.zip" \
    --file "$ZIP_PATH" \
    --content-type "application/zip"

echo "→ Uploading appcast.xml to R2..."
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
    wrangler r2 object put "$R2_BUCKET/appcast.xml" \
    --file dist/appcast.xml \
    --content-type "application/rss+xml" \
    --cache-control "no-cache"

echo ""
echo "✓ Published ZuluBar $VERSION"
echo "  Appcast: https://updates.zulubar.app/appcast.xml"
echo "  ZIP:     $URL"
