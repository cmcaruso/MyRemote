#!/bin/sh
# Packs MyRemote.app into build/MyRemote-<version>.dmg, to attach to a GitHub Release.
#
#   scripts/dmg.sh
#
# Builds the app with scripts/bundle.sh for both Apple Silicon and Intel, and signs it the same way
# (ad hoc unless scripts/signing.local names an identity). It builds into build/dmg/, so the app
# you run from build/ keeps its Accessibility grant. Without a Developer ID the app isn't
# notarized, so whoever downloads it approves it once in System Settings (see the README).
# The DMG holds the app and a link to /Applications to drag it onto.
set -eu
cd "$(dirname "$0")/.."

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
