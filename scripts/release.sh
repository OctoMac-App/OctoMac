#!/usr/bin/env bash
# Builds a release of OctoMac: a universal (Apple silicon and Intel) app, signed with the hardened runtime,
# optionally notarised, packed into a .dmg in ./dist.
#
#   scripts/release.sh                 # sign with the identity in scripts/release.local (or ad-hoc), make a .dmg
#   scripts/release.sh --notarize      # also notarise and staple (needs a notarytool keychain profile)
#   scripts/release.sh --bump patch    # bump ./VERSION first (major, minor or patch)
#
# Signing details never live in the repository. Put them in scripts/release.local (ignored by git):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="your-notarytool-profile"
# or pass them as environment variables. Without them the app is signed ad-hoc, which runs on your own Mac only.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[[ -f scripts/release.local ]] && source scripts/release.local
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE=false
BUMP=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --notarize) NOTARIZE=true; shift ;;
    --bump) BUMP="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
case "$BUMP" in
  major) MAJOR=$((MAJOR+1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR+1)); PATCH=0 ;;
  patch) PATCH=$((PATCH+1)) ;;
  "") ;;
  *) echo "--bump must be major, minor or patch" >&2; exit 1 ;;
esac
VERSION="$MAJOR.$MINOR.$PATCH"
[[ -n "$BUMP" ]] && printf '%s\n' "$VERSION" > VERSION
BUILD=$((MAJOR*10000 + MINOR*100 + PATCH))
echo "==> OctoMac $VERSION ($BUILD)"

echo "==> Running tests"
swift test >/dev/null

BINARIES=()
for ARCH in arm64 x86_64; do
  echo "==> Building $ARCH"
  swift build -c release --arch "$ARCH" --scratch-path ".build-$ARCH" >/dev/null 2>&1
  BINARIES+=("$(swift build -c release --arch "$ARCH" --scratch-path ".build-$ARCH" --show-bin-path)/OctoMac")
done

rm -rf dist && mkdir -p dist
APP="dist/OctoMac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/OctoMac"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns Support/OctoMark.png "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/OctoMac"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Signing ad-hoc (no SIGN_IDENTITY set)"
  codesign --force --sign - "$APP"
else
  echo "==> Signing with the hardened runtime"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

if [[ "$NOTARIZE" == true ]]; then
  [[ "$SIGN_IDENTITY" != "-" && -n "$NOTARY_PROFILE" ]] || { echo "Notarising needs SIGN_IDENTITY and NOTARY_PROFILE" >&2; exit 1; }
  echo "==> Notarising the app (uploads to Apple and waits)"
  ditto -c -k --keepParent "$APP" dist/notarize.zip
  xcrun notarytool submit dist/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  rm dist/notarize.zip
  xcrun stapler staple "$APP"
fi

echo "==> Making the disk image"
DMG="dist/OctoMac-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "OctoMac $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [[ "$NOTARIZE" == true ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  fi
fi
echo "==> Ready: $DMG"
