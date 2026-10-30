#!/bin/zsh
# Builds OctoMac.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c "$CONFIG"
BINS="$(swift build -c "$CONFIG" --show-bin-path)"

# Sign with your Developer ID when scripts/release.local names one, so macOS keeps treating every local build as
# the same app (Local Network and notification permissions stick). Otherwise sign ad-hoc.
[[ -f scripts/release.local ]] && source scripts/release.local
export SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="$(tr -d '[:space:]' < VERSION)"
NO_UPDATES=1 scripts/assemble.sh build/OctoMac.app "$BINS/OctoMac" "$BINS/OctoMacWidgets" \
  .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$VERSION" 1
echo "Built build/OctoMac.app"
