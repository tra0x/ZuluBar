#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH="${1:?Usage: scripts/publish-update.sh <zip-path> [notes]}"
NOTES="${2:-}"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"
: "${R2_BUCKET:?R2_BUCKET must be set}"
: "${SPARKLE_SIGN:?SPARKLE_SIGN must be set}"
: "${APP_PATH:?APP_PATH must be set}"

# Read version info directly from the built app
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST")

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

echo "→ Updating appcast.xml..."
DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
URL="https://updates.zulubar.app/ZuluBar-${VERSION}.zip"
NOTES_HTML="${NOTES:-Bug fixes and improvements.}"
# Guard against ]]> breaking CDATA
NOTES_HTML="${NOTES_HTML//]]>/]]]]><![CDATA[>}"

MARKER="    <!-- Items added here by \`make publish-update\` -->"
ITEM="    <item>
        <title>Version ${VERSION}</title>
        <pubDate>${DATE}</pubDate>
        <sparkle:version>${BUILD}</sparkle:version>
        <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        <description><![CDATA[<ul><li>${NOTES_HTML}</li></ul>]]></description>
        <enclosure url=\"${URL}\" length=\"${LENGTH}\" type=\"application/zip\" sparkle:edSignature=\"${SIG}\" />
    </item>"

APPCAST="dist/appcast.xml"
if ! grep -qF 'make publish-update' "$APPCAST"; then
    echo "Error: insertion marker not found in $APPCAST"; exit 1
fi

# Insert new item before the marker
ESCAPED_ITEM=$(printf '%s\n' "$ITEM" | sed 's/[&/\]/\\&/g')
sed -i '' "s|${MARKER}|${ESCAPED_ITEM}\\
${MARKER}|" "$APPCAST"

echo "  ✓ Appended entry for version $VERSION (build $BUILD)"

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
echo "✓ Published ZuluBar $VERSION (build $BUILD)"
echo "  Appcast: https://updates.zulubar.app/appcast.xml"
echo "  ZIP:     $URL"
