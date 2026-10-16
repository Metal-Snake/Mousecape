#!/usr/bin/env bash
#
# Builds dist/Mousecape.app from the SwiftPM products, without Xcode (the Command Line
# Tools are enough): release build → bundle → Info.plist, icon, launch agent → ad-hoc signing.
#
# Usage:
#   Scripts/build-app.sh            # just the .app
#   Scripts/build-app.sh --zip      # + dist/Mousecape.app.zip
#
set -euo pipefail

VERSION="2.0.0"     # CFBundleShortVersionString
BUILD="1"           # CFBundleVersion
AGENT_PLIST="io.github.metal-snake.Mousecape.agent.plist"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAKE_ZIP=0
[ "${1:-}" = "--zip" ] && MAKE_ZIP=1

APP="$ROOT/dist/Mousecape.app"

echo "==> Release build…"
swift build -c release --product Mousecape
swift build -c release --product mousecloak
BIN="$(swift build -c release --show-bin-path)"

echo "==> Bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/Mousecape" "$BIN/mousecloak" "$APP/Contents/MacOS/"
cp "Resources/$AGENT_PLIST" "$APP/Contents/Library/LaunchAgents/"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist" "$APP/Contents/Library/LaunchAgents/$AGENT_PLIST"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon…"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing…"
# Inner executable first, then the bundle (which seals the rest).
codesign --force --sign - --timestamp=none --identifier io.github.metal-snake.Mousecape.mousecloak \
    "$APP/Contents/MacOS/mousecloak"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Done: $APP"

if [ "$MAKE_ZIP" -eq 1 ]; then
    ditto -c -k --keepParent "$APP" "$ROOT/dist/Mousecape.app.zip"
    echo "==> Done: $ROOT/dist/Mousecape.app.zip"
fi
