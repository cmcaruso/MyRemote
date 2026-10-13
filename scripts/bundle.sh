#!/bin/sh
# Builds MyRemote.app into build/ and signs it.
#
#   scripts/bundle.sh          build and sign
#   scripts/bundle.sh --run    also quit the running Host and open the new one
#
# The app is built for this Mac's architecture. MYREMOTE_UNIVERSAL=1 builds it for both Apple Silicon
# and Intel, and MYREMOTE_OUT puts it in another folder than build/, as scripts/dmg.sh does for a
# release.
#
# MYREMOTE_UPDATES=1 turns on updates from GitHub Releases (Sparkle), as scripts/dmg.sh does: it sets
# the feed and the public key that checks each update and the feed itself (MYREMOTE_FEED_URL sets
# another feed, to try an update locally). Other builds don't update themselves, so a
# build from source never replaces itself with the published DMG.
#
# Signing is ad hoc by default. macOS ties the Accessibility grant to the signature, which an ad-hoc
# build changes every time, so each rebuild needs the grant again (--run resets the stale entry so
# macOS asks cleanly). If you rebuild the app often, sign with a stable identity of your own by
# setting MYREMOTE_SIGN_IDENTITY, and the grant survives rebuilds.
#
# Per-machine settings come from the environment or an untracked scripts/signing.local
# (see scripts/signing.local.example).
set -eu
cd "$(dirname "$0")/.."

[ -f scripts/signing.local ] && . scripts/signing.local
IDENTITY="${MYREMOTE_SIGN_IDENTITY:--}"
BUNDLE_ID="${MYREMOTE_BUNDLE_ID:-io.github.cmcaruso.myremote}"

if [ "$IDENTITY" != "-" ] && ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "No code-signing identity named \"$IDENTITY\" in your keychain." >&2
  echo "Unset MYREMOTE_SIGN_IDENTITY to sign ad hoc." >&2
  exit 1
fi

ARCHS=""
[ "${MYREMOTE_UNIVERSAL:-}" = 1 ] && ARCHS="--arch arm64 --arch x86_64"
swift build -c release --product MyRemoteHost $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/MyRemoteHost"

APP="${MYREMOTE_OUT:-build}/MyRemote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MyRemote"
rsync -a --exclude test remote/ "$APP/Contents/Resources/remote/"
sed "s/__BUNDLE_ID__/$BUNDLE_ID/" scripts/Info.plist > "$APP/Contents/Info.plist"
if [ "${MYREMOTE_UPDATES:-}" = 1 ]; then
  PLIST="$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${MYREMOTE_FEED_URL:-https://github.com/cmcaruso/MyRemote/releases/latest/download/appcast.xml}" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(cat scripts/sparkle-public-key)" "$PLIST"
  # The feed is signed with the same key, so its text and links can't be changed either. Sparkle then
  # also wants each update checked before it's unpacked.
  /usr/libexec/PlistBuddy -c "Add :SURequireSignedFeed bool true" -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$PLIST"
fi
# Sparkle, without its XPC services: only a sandboxed app needs them.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
  "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
cp LICENSE THIRD_PARTY_NOTICES.md scripts/AppIcon.icns "$APP/Contents/Resources/"
# The Swift packages' own licences and NOTICE files, which their Apache License asks every copy to carry.
scripts/licenses.sh "$APP/Contents/Resources/Licenses"

# Inside out, without --deep: Sparkle's helpers, the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$IDENTITY" "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$APP"
if [ "$IDENTITY" = "-" ]; then
  echo "Built $APP ($BUNDLE_ID, signed ad hoc: grant Accessibility again after this rebuild)"
else
  echo "Built $APP ($BUNDLE_ID, signed by \"$IDENTITY\")"
fi

if [ "${1:-}" = "--run" ]; then
  pkill -x MyRemote 2>/dev/null && sleep 0.5 || true
  if [ "$IDENTITY" = "-" ]; then
    # An ad-hoc rebuild leaves a stale Accessibility entry that looks on but no longer matches; clear it.
    # Quit System Settings first: if it's open it keeps showing the stale row, and turning that on
    # doesn't grant the new build.
    osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 || true
    # The grant lives under PostEvent (what CGRequestPostEventAccess asks for), not only Accessibility.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset PostEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "Grant Accessibility to MyRemote when macOS asks (System Settings → Privacy & Security → Accessibility)."
  fi
  open "$APP"
fi
