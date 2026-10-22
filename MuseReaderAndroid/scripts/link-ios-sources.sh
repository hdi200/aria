#!/bin/sh
# Links the iOS Swift files listed in ios-shared-sources.txt into the Android app
# (Aria/Sources/AriaSkip/Shared/), replacing the previous links. Links, not copies, so
# each file has one version for both apps.
set -eu

ANDROID_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_SOURCES="$ANDROID_DIR/../MuseReaderiOS/MuseReaderiOS"
SHARED_DIR="$ANDROID_DIR/Aria/Sources/AriaSkip/Shared"

find "$SHARED_DIR" -type l -delete 2>/dev/null || true
mkdir -p "$SHARED_DIR"

grep -vE '^\s*(#|$)' "$ANDROID_DIR/ios-shared-sources.txt" | while read -r path; do
  if [ ! -f "$IOS_SOURCES/$path" ]; then
    echo "missing: $path" >&2
    exit 1
  fi
  mkdir -p "$SHARED_DIR/$(dirname "$path")"
  # Relative link, so the checkout can move.
  depth=$(printf '%s' "Aria/Sources/AriaSkip/Shared/$path" | tr -cd '/' | wc -c | tr -d ' ')
  up=""
  i=0
  while [ "$i" -lt "$((depth + 1))" ]; do up="../$up"; i=$((i + 1)); done
  ln -s "${up}MuseReaderiOS/MuseReaderiOS/$path" "$SHARED_DIR/$path"
done
find "$SHARED_DIR" -type d -empty -delete
echo "Linked $(find "$SHARED_DIR" -type l | wc -l | tr -d ' ') iOS files into $SHARED_DIR"
