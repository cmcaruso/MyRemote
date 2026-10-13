#!/bin/sh
# Copies the licence and NOTICE files of every Swift package MyRemote is built with into a folder, for
# the app bundle: their licences (the Apache License 2.0, and Sparkle's MIT licence) ask that every copy
# of the app carries them.
#
#   scripts/licenses.sh <folder>
#
# Takes the packages pinned in Package.resolved from .build/checkouts, so run swift build first. A
# licence inside a package's sources (such as llhttp's in SwiftNIO) comes along, at the same path.
set -eu
cd "$(dirname "$0")/.."

OUT="$1"
rm -rf "$OUT"
mkdir -p "$OUT"
{
  echo "MyRemote is built with these Swift packages, all under the Apache License 2.0 except Sparkle,"
  echo "which is under the MIT License (its LICENSE also lists the licences of the code it includes)."
  echo "Each folder holds the package's own LICENSE and NOTICE files."
  echo
} > "$OUT/README.txt"

i=0
while ID="$(plutil -extract "pins.$i.identity" raw -o - Package.resolved 2>/dev/null)"; do
  VERSION="$(plutil -extract "pins.$i.state.version" raw -o - Package.resolved)"
  LOCATION="$(plutil -extract "pins.$i.location" raw -o - Package.resolved)"
  SRC=".build/checkouts/$ID"
  [ -d "$SRC" ] || { echo "No $SRC: run swift build first." >&2; exit 1; }
  echo "$ID $VERSION $LOCATION" >> "$OUT/README.txt"
  (cd "$SRC" && find . \( -path ./.git -o -path ./Tests -o -path ./Benchmarks \) -prune -o \
    -type f \( -iname 'license*' -o -iname 'notice*' \) -print) | while read -r FILE; do
    mkdir -p "$OUT/$ID/$(dirname "$FILE")"
    cp "$SRC/$FILE" "$OUT/$ID/$FILE"
  done
  i=$((i + 1))
done
[ "$i" -gt 0 ] || { echo "No packages found in Package.resolved." >&2; exit 1; }
