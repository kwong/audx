#!/bin/bash

# build.sh - Build audx via xcodebuild and stage audx.app at the repo root.

set -euo pipefail

APP_NAME="audx"
VERSION="${VERSION:-0.0.0-dev}"
PROJECT_PATH="${APP_NAME}.xcodeproj"
SCHEME_NAME="${APP_NAME}"
DERIVED_DATA_PATH=".build/xcode"
BUILD_CONFIGURATION="Release"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${BUILD_CONFIGURATION}/${APP_NAME}.app"
STAGED_APP_PATH="${APP_NAME}.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Error: xcodebuild is not available. Install full Xcode and make sure it is the active developer directory." >&2
    exit 1
fi

echo "Building Xcode project (${VERSION})..."
rm -rf "${DERIVED_DATA_PATH}" "${STAGED_APP_PATH}"

xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${BUILD_CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${VERSION}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=YES \
    build

if [ ! -d "${BUILT_APP_PATH}" ]; then
    echo "Error: expected built app at ${BUILT_APP_PATH}" >&2
    exit 1
fi

cp -R "${BUILT_APP_PATH}" "${STAGED_APP_PATH}"
touch "${STAGED_APP_PATH}"

echo "App bundle created at ${STAGED_APP_PATH}"
