#!/bin/sh
# Builds MyRemote.app into build/ and signs it with a stable identity, so macOS keeps the
# Accessibility grant across rebuilds (an ad-hoc signature loses it every build).
#
#   scripts/bundle.sh          build and sign
#   scripts/bundle.sh --run    also quit the running Host and open the new one
#
# Per-machine settings come from the environment or an untracked scripts/signing.local
# (see scripts/signing.local.example).
set -eu
cd "$(dirname "$0")/.."

[ -f scripts/signing.local ] && . scripts/signing.local
IDENTITY="${MYREMOTE_SIGN_IDENTITY:-MyRemote Signing}"
BUNDLE_ID="${MYREMOTE_BUNDLE_ID:-io.github.cmcaruso.myremote}"

if [ "$IDENTITY" = "-" ]; then
  echo "warning: ad-hoc signing; macOS will ask for Accessibility again after every rebuild." >&2
elif ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "No code-signing identity named \"$IDENTITY\" in your keychain." >&2
  echo "Create one (README → Build from source → Signing), or set MYREMOTE_SIGN_IDENTITY=- to sign ad hoc." >&2
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

codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP ($BUNDLE_ID, signed by \"$IDENTITY\")"

if [ "${1:-}" = "--run" ]; then
  pkill -x MyRemote 2>/dev/null && sleep 0.5 || true
  open "$APP"
fi
