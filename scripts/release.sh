#!/usr/bin/env bash
# Build, sign, notarize, staple a DMG of xFractal and regenerate the
# Sparkle appcast. Mirrors the AudioXplorer / GraphClick release scripts
# described in INSTRUCTIONS.md.
#
# Usage:
#   ./scripts/release.sh                       # full pipeline
#   SKIP_NOTARIZE=1 ./scripts/release.sh       # skip notarytool (fast iter)
#   NOTARY_PROFILE=XF_NOTARY ./scripts/release.sh
#
# Requires:
#   - xcodegen (brew install xcodegen)
#   - create-dmg (brew install create-dmg)
#   - Developer ID Application certificate in login keychain
#   - notarytool keychain profile (default: XF_NOTARY); see INSTRUCTIONS.md §1.3
#   - Sparkle EdDSA private key in login keychain (shared across apps)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-xFractal}"
SCHEME="${SCHEME:-xFractal}"
NOTARY_PROFILE="${NOTARY_PROFILE:-XF_NOTARY}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
GH_OWNER="${GH_OWNER:-jean-bovet}"
GH_REPO="${GH_REPO:-xFractal}"

cd "$PROJECT_DIR"

PLIST_PATH="$PROJECT_DIR/xFractal/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST_PATH")
if [[ -z "$VERSION" ]]; then
    echo "ERROR: could not read CFBundleShortVersionString from $PLIST_PATH" >&2
    exit 1
fi
echo "▶︎ Releasing $APP_NAME $VERSION"

echo "▶︎ Generating Xcode project"
xcodegen generate >/dev/null

BUILD_DIR="$PROJECT_DIR/build"
DERIVED="$BUILD_DIR/DerivedData"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▶︎ Building Release (unsigned — will sign explicitly below)"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
test -d "$APP_PATH" || { echo "ERROR: $APP_PATH not found"; exit 1; }

ENTITLEMENTS="$PROJECT_DIR/$APP_NAME.entitlements"
test -f "$ENTITLEMENTS" || { echo "ERROR: $ENTITLEMENTS not found"; exit 1; }

echo "▶︎ Signing app bundle (hardened runtime, entitlements, timestamp)"
# Re-sign nested code first (Sparkle's XPC services + Updater.app), then the
# outer bundle. --deep alone misses some nested binaries on recent macOS.
find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" -o -name "*.app" -o -name "*.xpc" 2>/dev/null | while read -r nested; do
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" --generate-entitlement-der \
        "$nested" 2>/dev/null || true
done
codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" --generate-entitlement-der \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

DIST_DIR="$PROJECT_DIR/dist"
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"

echo "▶︎ Building DMG → $DMG_PATH"
create-dmg \
    --volname "$APP_NAME $VERSION" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 130 180 \
    --app-drop-link 410 180 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

echo "▶︎ Signing DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "▶︎ SKIP_NOTARIZE=1 — skipping notarization + appcast"
    echo "Done (unnotarized): $DMG_PATH"
    exit 0
fi

echo "▶︎ Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▶︎ Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

GENERATE_APPCAST="$PROJECT_DIR/scripts/sparkle/generate_appcast"
DOCS_DIR="$PROJECT_DIR/docs"
if [[ -x "$GENERATE_APPCAST" ]]; then
    echo "▶︎ Regenerating appcast → docs/appcast.xml"
    mkdir -p "$DOCS_DIR"
    "$GENERATE_APPCAST" "$DIST_DIR" \
        --download-url-prefix "https://github.com/$GH_OWNER/$GH_REPO/releases/download/v$VERSION/" \
        -o "$DOCS_DIR/appcast.xml"
fi

echo "✅ Done: $DMG_PATH"
echo
echo "Next:"
echo "  git add docs/appcast.xml xFractal/Info.plist"
echo "  git commit -m \"Release $VERSION\""
echo "  git tag -a v$VERSION -m \"$APP_NAME $VERSION\""
echo "  git push origin main --tags"
echo "  gh release create v$VERSION \"$DMG_PATH\" --title \"$APP_NAME $VERSION\""
