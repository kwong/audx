#!/bin/bash

# build.sh - Script to build audx directly using swiftc to bypass SPM xcbuild issues

set -e

APP_NAME="audx"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building Swift Source..."
mkdir -p "$BUILD_DIR"
swiftc -O -whole-module-optimization Sources/audx/*.swift \
    -o "$BUILD_DIR/$APP_NAME" \
    -framework SwiftUI -framework AppKit -framework CoreAudio -framework IOBluetooth -framework Carbon -framework UserNotifications

echo "Creating App Bundle Structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying Executable..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "Copying Assets..."
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/"
fi

echo "Creating PkgInfo..."
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.kangwei.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Audx requires audio access to monitor playing audio and switch outputs.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Audx uses Bluetooth to automatically disconnect idle devices.</string>
</dict>
</plist>
EOF

echo "Forcing LaunchServices reload..."
touch "$APP_DIR"

echo "App bundle created at $APP_DIR"
