#!/usr/bin/env bash
#
# Build Release, replace the copy in /Applications, relaunch it.
#
#   Tools/release.sh
#
# Use this instead of Xcode's Archive → Distribute flow. There are no
# code signing identities on this machine, so App Store Connect and
# Direct Distribution aren't options; the app is ad-hoc signed, which is
# fine for a locally built tool that was never quarantined.
#
# Preferences and the switching script live outside the bundle, so
# replacing the app never resets your setup.

set -euo pipefail

SCHEME="ToggleMicDistance"
APP_NAME="ToggleMicDistance.app"
DEST="/Applications/$APP_NAME"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$PROJECT_ROOT/$SCHEME.xcodeproj"

# Guard against a typo turning `rm -rf` loose on something else.
if [ "$DEST" != "/Applications/$APP_NAME" ] || [ -z "$APP_NAME" ]; then
  echo "Refusing to touch '$DEST'" >&2
  exit 1
fi

echo "==> Building Release"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -destination 'platform=macOS' \
  -quiet build

BUILD_DIR="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | sed -n 's/^ *CONFIGURATION_BUILD_DIR = //p' | head -1
)"
SRC="$BUILD_DIR/$APP_NAME"

if [ ! -d "$SRC" ]; then
  echo "No app was built at: $SRC" >&2
  exit 1
fi

echo "==> Stopping any running copy"
# Matches both the /Applications copy and any Xcode debug instance, so
# you don't end up with two icons in the menu bar.
pkill -f "$APP_NAME/Contents/MacOS" 2>/dev/null || true
sleep 1

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

# Every build registers its DerivedData copy with LaunchServices (see the
# `lsregister -f -R -trusted` step in the build log), and registered apps
# show up in Spotlight. That means Spotlight offers a stale Debug build
# ahead of the installed one, and launching it puts an out of date icon in
# the menu bar, which is confusing to debug. Unregister them; the copy in
# /Applications is the only one that should be findable.
echo "==> Unregistering DerivedData copies from Spotlight"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions"
LSREGISTER="$LSREGISTER/Current/Frameworks/LaunchServices.framework"
LSREGISTER="$LSREGISTER/Versions/Current/Support/lsregister"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
for dir in "$DERIVED/$SCHEME"-*; do
  [ -d "$dir" ] && [ -x "$LSREGISTER" ] || continue
  find "$dir" -name "$APP_NAME" -type d -print0 2>/dev/null \
    | xargs -0 -I {} "$LSREGISTER" -u {} 2>/dev/null || true
done

echo "==> Launching"
open "$DEST"

echo
VERSION="$(
  defaults read "$DEST/Contents/Info" CFBundleShortVersionString \
    2>/dev/null || echo "?"
)"
echo "Installed $VERSION from $SRC"
echo "If Finder or the Dock shows a stale icon, run: killall Dock"
