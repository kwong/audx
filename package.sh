#!/bin/bash

# package.sh - Builds audx and produces a .pkg installer.
# Usage: VERSION=1.2.3 ./package.sh

set -e

if [ -z "$VERSION" ]; then
    echo "Error: VERSION env var is required (e.g. VERSION=1.2.3 ./package.sh)" >&2
    exit 1
fi

APP_NAME="audx"
PKG_NAME="${APP_NAME}-${VERSION}.pkg"
STAGING_DIR=".pkg-staging"

echo "Building app bundle (version $VERSION)..."
export VERSION
./build.sh

echo "Staging app bundle..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "${APP_NAME}.app" "$STAGING_DIR/"

echo "Creating package..."
pkgbuild \
    --root "$STAGING_DIR" \
    --identifier "com.kwong.${APP_NAME}" \
    --version "$VERSION" \
    --install-location /Applications \
    "$PKG_NAME"

rm -rf "$STAGING_DIR"

echo "Package created: $PKG_NAME"
