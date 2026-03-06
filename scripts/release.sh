#!/bin/bash
set -euo pipefail

# SillyTrack Release Script
# Usage: ./scripts/release.sh <version> <build_number>
# Example: ./scripts/release.sh 1.2.0 3

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
SPARKLE_BIN="$PROJECT_DIR/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin"

VERSION="${1:-}"
BUILD_NUM="${2:-}"
if [ -z "$VERSION" ] || [ -z "$BUILD_NUM" ]; then
    echo "Usage: $0 <version> <build_number>"
    echo "Example: $0 1.2.0 3"
    echo ""
    echo "  version     = marketing version (e.g. 1.2.0)"
    echo "  build_number = integer build number, must be higher than previous (e.g. 3)"
    exit 1
fi

echo "==> Building SillyTrack v$VERSION (build $BUILD_NUM) Release..."
cd "$PROJECT_DIR"

xcodebuild -project WorkTracker.xcodeproj \
    -scheme WorkTracker \
    -configuration Release \
    -derivedDataPath .build/xcode \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    build

echo "==> Creating release archive..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

APP_PATH=".build/xcode/Build/Products/Release/SillyTrack.app"
ZIP_NAME="SillyTrack-${VERSION}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Signing update with Sparkle..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>&1)
ED_SIGNATURE=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(stat -f%z "$ZIP_PATH")

echo "==> Generating appcast entry..."
DOWNLOAD_URL="https://github.com/sicmundu/silly-tracker/releases/download/v${VERSION}/${ZIP_NAME}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")

cat > "$BUILD_DIR/appcast_item.xml" << XMLEOF
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUM</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure
                url="$DOWNLOAD_URL"
                length="$LENGTH"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIGNATURE"
            />
        </item>
XMLEOF

echo ""
echo "=== RELEASE READY ==="
echo "ZIP:       $ZIP_PATH"
echo "Version:   $VERSION (build $BUILD_NUM)"
echo "Signature: $ED_SIGNATURE"
echo "Size:      $LENGTH bytes"
echo ""
echo "Next steps:"
echo "  1. Copy the content from $BUILD_DIR/appcast_item.xml"
echo "  2. Add it to appcast.xml inside <channel>"
echo "  3. Commit and push appcast.xml"
echo "  4. Create GitHub release v$VERSION and upload $ZIP_PATH"
echo ""
echo "  Or use gh CLI:"
echo "    gh release create v$VERSION '$ZIP_PATH' --title 'v$VERSION' --notes 'Release $VERSION'"
