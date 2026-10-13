#!/bin/sh
# Packs MyRemote.app into build/MyRemote-<version>.dmg, and writes build/appcast.xml, the feed the
# installed apps check for updates. Attach both to a GitHub Release.
#
#   scripts/dmg.sh
#   MYREMOTE_NOTES=notes.md scripts/dmg.sh    also show these release notes in the update window
#
# Builds the app with scripts/bundle.sh for both Apple Silicon and Intel, with updates on, and signs
# it with the identity scripts/signing.local names. A Release must not be signed ad hoc: the next
# version would have another signature, and macOS would drop the Accessibility grant on every
# update. It builds into build/dmg/, so the app you run from build/ keeps its Accessibility grant.
# Sparkle signs the update with the EdDSA key in your login keychain (made once with generate_keys,
# its public half in scripts/sparkle-public-key). Without a Developer ID the app isn't
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

[ -f scripts/signing.local ] && . scripts/signing.local
if [ -z "${MYREMOTE_SIGN_IDENTITY:-}" ] || [ "$MYREMOTE_SIGN_IDENTITY" = "-" ]; then
  echo "Set MYREMOTE_SIGN_IDENTITY in scripts/signing.local: a Release signed ad hoc loses the Accessibility grant on every update." >&2
  exit 1
fi

MYREMOTE_UNIVERSAL=1 MYREMOTE_UPDATES=1 MYREMOTE_OUT=build/dmg scripts/bundle.sh

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

# The feed lists only this version: installed apps fetch it from the latest Release, whatever
# version they are on.
FEED="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$FEED"' EXIT
cp "$DMG" "$FEED/"
NOTES=""
if [ -n "${MYREMOTE_NOTES:-}" ]; then
  cp "$MYREMOTE_NOTES" "$FEED/MyRemote-$VERSION.md"
  NOTES="--embed-release-notes"
fi
RELEASE="https://github.com/cmcaruso/MyRemote/releases"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast $NOTES \
  --download-url-prefix "$RELEASE/download/v$VERSION/" --full-release-notes-url "$RELEASE/tag/v$VERSION" \
  -o build/appcast.xml "$FEED"
echo "Built build/appcast.xml"

if git tag --points-at HEAD | grep -qx "v$VERSION"; then
  echo "From tag v$VERSION: attach $DMG and build/appcast.xml to that tag's Release."
else
  echo "Warning: HEAD isn't tagged v$VERSION. Tag it (git tag v$VERSION) and push the tag, so the Release's source matches this DMG." >&2
fi
