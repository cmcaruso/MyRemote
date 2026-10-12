#!/bin/sh
# Builds MyRemote.app into build/ and signs it.
#
#   scripts/bundle.sh          build and sign
#   scripts/bundle.sh --run    also quit the running Host and open the new one
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

swift build -c release --product MyRemoteHost
BIN="$(swift build -c release --show-bin-path)/MyRemoteHost"

APP=build/MyRemote.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MyRemote"
rsync -a --exclude test remote/ "$APP/Contents/Resources/remote/"
sed "s/__BUNDLE_ID__/$BUNDLE_ID/" scripts/Info.plist > "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

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
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "Grant Accessibility to MyRemote when macOS asks (System Settings → Privacy & Security → Accessibility)."
  fi
  open "$APP"
fi
