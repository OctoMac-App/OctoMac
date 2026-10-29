#!/usr/bin/env bash
# Puts OctoMac.app together and signs it. Used by build-app.sh and release.sh.
#
#   scripts/assemble.sh APP APP_BINARY WIDGETS_BINARY SPARKLE_FRAMEWORK VERSION BUILD
#
# SIGN_IDENTITY (optional) is a Developer ID; without one the app is signed ad-hoc. Set TIMESTAMP=1 for releases.
set -euo pipefail
APP="$1"; BIN="$2"; WIDGETS_BIN="$3"; SPARKLE="$4"; VERSION="$5"; BUILD="$6"
IDENTITY="${SIGN_IDENTITY:--}"
PB=/usr/libexec/PlistBuddy

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/PlugIns"
cp "$BIN" "$APP/Contents/MacOS/OctoMac"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns Support/OctoMark.png Support/DemoCamera.jpg "$APP/Contents/Resources/"
$PB -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Sparkle (automatic updates). OctoMac isn't sandboxed, so Sparkle's XPC services aren't needed.
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# Desktop and Control Centre widgets.
APPEX="$APP/Contents/PlugIns/OctoMacWidgets.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$WIDGETS_BIN" "$APPEX/Contents/MacOS/OctoMacWidgets"
cp Support/Widgets/Info.plist "$APPEX/Contents/Info.plist"
$PB -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APPEX/Contents/Info.plist"

# Translations, from the String Catalog, for the app and its widgets.
mkdir -p "$APPEX/Contents/Resources"
for RESOURCES in "$APP/Contents/Resources" "$APPEX/Contents/Resources"; do
  xcrun xcstringstool compile Support/Localization/Localizable.xcstrings --output-directory "$RESOURCES" >/dev/null
done
# The permission message and file kinds macOS shows on OctoMac's behalf.
xcrun xcstringstool compile Support/Localization/InfoPlist.xcstrings --output-directory "$APP/Contents/Resources" >/dev/null

# Sign from the inside out, each part with the hardened runtime; the widgets get their sandbox entitlements.
FLAGS=(--force --options runtime --sign "$IDENTITY")
[[ "${TIMESTAMP:-0}" == 1 && "$IDENTITY" != "-" ]] && FLAGS+=(--timestamp)
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for ITEM in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK"; do
  codesign "${FLAGS[@]}" "$ITEM" >/dev/null 2>&1
done
codesign "${FLAGS[@]}" --entitlements Support/Widgets/Widgets.entitlements "$APPEX" >/dev/null 2>&1
codesign "${FLAGS[@]}" "$APP" >/dev/null 2>&1
codesign --verify --strict "$APP"
