#!/bin/sh
# Packs MyRemote.app into build/MyRemote-<version>.dmg, to attach to a GitHub Release.
#
#   scripts/dmg.sh
#
# Builds the app with scripts/bundle.sh for both Apple Silicon and Intel, and signs it the same way
# (ad hoc unless scripts/signing.local names an identity). It builds into build/dmg/, so the app
# you run from build/ keeps its Accessibility grant. Without a Developer ID the app isn't
# notarized, so whoever downloads it approves it once in System Settings (see the README).
# The DMG holds the app and a link to /Applications to drag it onto. It must be built from a clean
# tree, and from the commit tagged v<version>, whose source GitHub attaches to the Release.
set -eu
cd "$(dirname "$0")/.."

# A DMG's source is the tag it's released under (GPL-3.0 asks for the exact source of each binary), so
# build only from committed code.
if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree has uncommitted changes; commit them first, so the DMG matches a commit." >&2
  exit 1
fi

MYREMOTE_UNIVERSAL=1 MYREMOTE_OUT=build/dmg scripts/bundle.sh

APP=build/dmg/MyRemote.app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/MyRemote-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/MyRemote.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "MyRemote $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
echo "Built $DMG"
if git tag --points-at HEAD | grep -qx "v$VERSION"; then
  echo "From tag v$VERSION: attach it to that tag's Release."
else
  echo "Warning: HEAD isn't tagged v$VERSION. Tag it (git tag v$VERSION) and push the tag, so the Release's source matches this DMG." >&2
fi
