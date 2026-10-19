#!/usr/bin/env bash
#
# Builds dist/Mousecape.app from the SwiftPM products, without Xcode (the Command Line
# Tools are enough): release build → bundle → Info.plist, icon, launch agent → signing.
#
# Signing uses the "Mousecape Code Signing" certificate when the keychain has it (see
# Scripts/make-signing-certificate.sh), so every build keeps the same identity; otherwise
# the build is ad-hoc signed. SIGN_IDENTITY overrides both (a certificate name or SHA-1, or
# "-" for ad-hoc).
#
# Usage:
#   Scripts/build-app.sh            # just the .app
#   Scripts/build-app.sh --zip      # + dist/Mousecape.app.zip
#
set -euo pipefail

VERSION="2.0.0"     # CFBundleShortVersionString
BUILD="1"           # CFBundleVersion

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Mousecape" "$BIN/mousecloak" "$APP/Contents/MacOS/"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon…"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

CERT_NAME="Mousecape Code Signing"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-certificate -c "$CERT_NAME" -Z 2>/dev/null | awk '/SHA-1/ { print $NF; exit }')"
fi
if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_IDENTITY="-"
    echo "==> Ad-hoc signing (no \"$CERT_NAME\" certificate)…"
else
    echo "==> Signing with $SIGN_IDENTITY…"
fi
# Inner executable first, then the bundle (which seals the rest).
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --identifier io.github.metal-snake.Mousecape.mousecloak \
    "$APP/Contents/MacOS/mousecloak"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Done: $APP"

if [ "$MAKE_ZIP" -eq 1 ]; then
    ditto -c -k --keepParent "$APP" "$ROOT/dist/Mousecape.app.zip"
    echo "==> Done: $ROOT/dist/Mousecape.app.zip"
fi
