#!/bin/zsh
# Builds OctoMac.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/OctoMac"

APP="build/OctoMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OctoMac"
cp Support/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(tr -d '[:space:]' < VERSION)" "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/OctoMark.png Support/DemoCamera.jpg "$APP/Contents/Resources/"
# Sparkle (automatic updates). OctoMac isn't sandboxed, so Sparkle's XPC services aren't needed.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
# Sign with your Developer ID when scripts/release.local names one, so macOS keeps treating every local build as
# the same app (Local Network and notification permissions stick). Otherwise sign ad-hoc.
[[ -f scripts/release.local ]] && source scripts/release.local
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$APP" >/dev/null
echo "Built $APP"
