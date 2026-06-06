#!/bin/bash

# package.sh - Builds audx and produces both .pkg and .dmg release assets.
# Usage: VERSION=1.2.3 ./package.sh

set -e

if [ -z "$VERSION" ]; then
    echo "Error: VERSION env var is required (e.g. VERSION=1.2.3 ./package.sh)" >&2
    exit 1
fi

APP_NAME="audx"
APP_BUNDLE="${APP_NAME}.app"
PKG_NAME="${APP_NAME}-${VERSION}.pkg"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
PKG_STAGING_DIR=".pkg-staging"
DMG_STAGING_DIR=".dmg-staging"

echo "Building app bundle (version $VERSION)..."
export VERSION
./build.sh

echo "Verifying app bundle version..."
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [ "$BUNDLE_VERSION" != "$VERSION" ]; then
    echo "Error: built app bundle version '$BUNDLE_VERSION' does not match expected version '$VERSION'" >&2
    exit 1
fi

echo "Staging app bundle for pkg..."
rm -rf "$PKG_STAGING_DIR"
mkdir -p "$PKG_STAGING_DIR"
cp -R "$APP_BUNDLE" "$PKG_STAGING_DIR/"

echo "Creating pkg..."
pkgbuild \
    --root "$PKG_STAGING_DIR" \
    --identifier "com.wkngw.${APP_NAME}" \
    --version "$VERSION" \
    --install-location /Applications \
    "$PKG_NAME"

echo "Staging app bundle for dmg..."
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

echo "Creating dmg..."
rm -f "$DMG_NAME"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

rm -rf "$PKG_STAGING_DIR" "$DMG_STAGING_DIR"

echo "Package created: $PKG_NAME"
echo "Disk image created: $DMG_NAME"
