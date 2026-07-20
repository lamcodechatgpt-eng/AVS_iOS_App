#!/usr/bin/env bash
# Build AVS_iOS_App locally on macOS. No GitHub account or Actions required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build-local"
PROJECT="$ROOT/AVS_iOS_App.xcodeproj"
SCHEME="AVS_iOS_App"
IPA="$ROOT/Builds/AVS_iOS_App-local.ipa"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_command xcodebuild
require_command xcrun
require_command xcodegen

cd "$ROOT"
xcodegen generate

# Select the first available iPhone simulator instead of hard-coding a model.
SIMULATOR_ID="$(xcrun simctl list devices available | sed -nE '/iPhone .*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No available iPhone Simulator found. Install one in Xcode Settings > Components." >&2
  exit 1
fi

mkdir -p "$ROOT/Builds"
rm -rf "$BUILD_DIR"

echo "Running unit tests…"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$BUILD_DIR/tests" \
  -resultBundlePath "$BUILD_DIR/TestResults.xcresult" \
  CODE_SIGNING_ALLOWED=NO

echo "Building unsigned Release app…"
xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination generic/platform=iOS \
  -derivedDataPath "$BUILD_DIR/release" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE="" \
  CODE_SIGNING_ALLOWED=NO

APP="$BUILD_DIR/release/Build/Products/Release-iphoneos/AVS_iOS_App.app"
if [[ ! -d "$APP" ]]; then
  echo "Release app was not produced at: $APP" >&2
  exit 1
fi

PAYLOAD="$BUILD_DIR/Payload"
rm -rf "$PAYLOAD" "$IPA"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"
ditto -c -k --sequesterRsrc --keepParent "$PAYLOAD" "$IPA"

echo "Done: $IPA"
echo "Test result: $BUILD_DIR/TestResults.xcresult"
