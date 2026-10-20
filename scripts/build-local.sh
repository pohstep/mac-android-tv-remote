#!/bin/bash
# Build Mac Android TV Remote with swiftc (no Xcode needed), assemble the .app, sign, install, relaunch.
#
#   SIGN_IDENTITY   codesign identity name. Unset = ad-hoc ("-"). A stable self-signed identity keeps
#                   the keychain "Always Allow" and the Accessibility grant across rebuilds.
#   APP_NAME        bundle folder name (default "Mac Android TV Remote")
#   BUNDLE_ID       default app.pohstep.remote
#   INSTALL_DIR     default ~/Applications
#   NO_INSTALL=1    build and sign only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
APP_NAME="${APP_NAME:-Mac Android TV Remote}"
BUNDLE_ID="${BUNDLE_ID:-app.pohstep.remote}"
EXE="Pohstep Remote"
SIGN="${SIGN_IDENTITY:--}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP="dist/$APP_NAME.app"
ARCH="${ARCH:-$(uname -m)}"

mkdir -p dist
swiftc -O -target "$ARCH-apple-macos13.0" -parse-as-library -module-name PohstepRemote \
  Sources/TvRemoteCore/*.swift macos/PohstepRemote/*.swift -o dist/PohstepRemote

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp dist/PohstepRemote "$APP/Contents/MacOS/$EXE"
sed -e "s/\$(EXECUTABLE_NAME)/$EXE/" -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e 's/\$(PRODUCT_NAME)/Mac Android TV Remote/' -e 's/\$(DEVELOPMENT_LANGUAGE)/en/' \
    macos/PohstepRemote/Info.plist > "$APP/Contents/Info.plist"
iconutil -c icns assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp assets/menubar-template.png assets/menubar-template@2x.png "$APP/Contents/Resources/"
codesign --force --deep --sign "$SIGN" "$APP"
echo "Built and signed ($SIGN): $APP"

[ "${NO_INSTALL:-0}" = 1 ] && exit 0
pkill -f "$APP_NAME.app/Contents/MacOS/$EXE" 2>/dev/null || true
sleep 1
mkdir -p "$INSTALL_DIR"; rm -rf "$INSTALL_DIR/$APP_NAME.app"
ditto "$APP" "$INSTALL_DIR/$APP_NAME.app"
touch "$INSTALL_DIR/$APP_NAME.app"
open "$INSTALL_DIR/$APP_NAME.app"
