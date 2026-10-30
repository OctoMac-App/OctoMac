#!/usr/bin/env bash
# Publishes the website (website/, built into every language by scripts/build-site.py, plus the screenshots in docs/)
# to OctoMac-App/octomac-app.github.io, which GitHub Pages serves at https://octomac-app.github.io/. Run it after
# changing the website or its screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."

SITE="$(mktemp -d)"
trap 'rm -rf "$SITE"' EXIT
git clone -q git@github.com:OctoMac-App/octomac-app.github.io.git "$SITE"
git -C "$SITE" checkout -q -B master

# Replace everything but the repository itself with a fresh copy.
find "$SITE" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
scripts/build-site.py check
scripts/build-site.py build "$SITE"
cp -R docs/screenshots "$SITE/screenshots"
cp docs/social-preview.png "$SITE/"
touch "$SITE/.nojekyll"
cat > "$SITE/README.md" <<'README'
# octomac-app.github.io

The OctoMac website, served at https://octomac-app.github.io/.

Please don't edit this repository directly. The site is built from `website/` in
[OctoMac-App/OctoMac](https://github.com/OctoMac-App/OctoMac) and published here by `scripts/publish-site.sh`.
README

git -C "$SITE" add -A
if git -C "$SITE" diff --cached --quiet; then
  echo "The website is already up to date."
else
  git -C "$SITE" commit -q -m "Website from OctoMac $(git rev-parse --short HEAD)"
  git -C "$SITE" push -q origin master
  echo "Published the website to https://octomac-app.github.io/"
fi
