#!/bin/bash
# Build Zapbar with swiftc (no Xcode needed), assemble the .app, sign, install, relaunch.
#
#   SIGN_IDENTITY   codesign identity name. Unset = ad-hoc ("-"). A stable self-signed identity keeps
#                   the keychain "Always Allow" and the Accessibility grant across rebuilds.
#   APP_NAME        bundle folder name (default "Zapbar")
#   BUNDLE_ID       default com.pohstep.tvremote
#   INSTALL_DIR     default ~/Applications
#   NO_INSTALL=1    build and sign only
#   SANDBOX=1       App Sandbox build. Embeds a local adb and signs with the entitlements files.
#                   Does not download adb. Requires PLATFORM_TOOLS or ADB_BINARY on this machine.
#   PLATFORM_TOOLS  directory that contains adb and NOTICE.txt (default ./platform-tools)
#   ADB_BINARY      adb executable (default $PLATFORM_TOOLS/adb)
#   ZAPBAR_ADVANCED  default 0. Leave unset for a release build. scripts/build-dev.sh sets it to 1.
#   ZAPBAR_MIGRATE_V1  default 0. Release and sandbox builds do not read the v1.0 settings
#                   folder or the old keychain item. scripts/build-dev.sh sets it to 1.
#                   A sandbox compile still skips that migration.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
APP_NAME="${APP_NAME:-Zapbar}"
BUNDLE_ID="${BUNDLE_ID:-com.pohstep.tvremote}"
EXE="Zapbar"
SIGN="${SIGN_IDENTITY:--}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP="dist/$APP_NAME.app"
ARCH="${ARCH:-universal}"
PLATFORM_TOOLS="${PLATFORM_TOOLS:-$ROOT/platform-tools}"
ADB_BINARY="${ADB_BINARY:-$PLATFORM_TOOLS/adb}"
SANDBOX="${SANDBOX:-0}"

notice_file() {
  local dir candidate
  dir="$(cd "$(dirname "$ADB_BINARY")" && pwd)"
  for candidate in "$PLATFORM_TOOLS/NOTICE.txt" "$PLATFORM_TOOLS/NOTICE" "$dir/NOTICE.txt" "$dir/NOTICE"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

canon_arch() {
  case "$1" in
    arm64|aarch64) printf '%s\n' arm64 ;;
    x86_64|amd64) printf '%s\n' x86_64 ;;
    *) return 1 ;;
  esac
}

require_archs() {
  local label="$1" got="$2" arch
  for arch in "${ARCH_LIST[@]}"; do
    case " $got " in
      *" $arch "*) ;;
      *) echo "$label is missing $arch (lipo -archs: $got)" >&2; exit 1 ;;
    esac
  done
}

if [ "$ARCH" = host ]; then
  ARCH="$(uname -m)"
fi

ARCH_LIST=()
case "$ARCH" in
  universal|all)
    ARCH_LIST=(arm64 x86_64)
    ;;
  *)
    one="$(canon_arch "$ARCH")" || {
      echo "ARCH must be universal, arm64, x86_64, or host (got $ARCH)" >&2
      exit 1
    }
    ARCH_LIST=("$one")
    ;;
esac

if [ "$SANDBOX" = 1 ]; then
  if [ ! -f "$ADB_BINARY" ]; then
    echo "SANDBOX=1 needs a local adb at $ADB_BINARY. Put platform-tools on this Mac; the script does not download it." >&2
    exit 1
  fi
  if ! notice_file >/dev/null; then
    echo "SANDBOX=1 needs the platform-tools NOTICE or NOTICE.txt next to adb (Apache-2.0). Refusing to embed adb without it. See docs/adb-notice.md." >&2
    exit 1
  fi
  require_archs "adb at $ADB_BINARY" "$(lipo -archs "$ADB_BINARY")"
fi

mkdir -p dist
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_FLAGS=(-O -parse-as-library -module-name PohstepRemote -sdk "$SDK")
if [ "$SANDBOX" = 1 ]; then
  SWIFT_FLAGS+=(-DSANDBOX_BUILD)
fi
# Release builds leave this unset, so clean-up is not compiled into the app.
if [ "${ZAPBAR_ADVANCED:-0}" = 1 ]; then
  SWIFT_FLAGS+=(-DZAPBAR_ADVANCED)
fi
if [ "${ZAPBAR_MIGRATE_V1:-0}" = 1 ]; then
  SWIFT_FLAGS+=(-DZAPBAR_MIGRATE_V1)
fi
SLICES=()
for arch in "${ARCH_LIST[@]}"; do
  slice="dist/PohstepRemote.$arch"
  rm -rf "dist/ModuleCache.$arch"
  xcrun --sdk macosx swiftc "${SWIFT_FLAGS[@]}" -target "$arch-apple-macos13.0" \
    -module-cache-path "dist/ModuleCache.$arch" \
    Sources/TvRemoteCore/*.swift macos/PohstepRemote/*.swift \
    -lz -framework ServiceManagement -o "$slice"
  SLICES+=("$slice")
done
rm -f dist/PohstepRemote
if [ "${#SLICES[@]}" -eq 1 ]; then
  mv "${SLICES[0]}" dist/PohstepRemote
else
  lipo -create "${SLICES[@]}" -output dist/PohstepRemote
  rm -f "${SLICES[@]}"
fi
rm -rf dist/ModuleCache.arm64 dist/ModuleCache.x86_64

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp dist/PohstepRemote "$APP/Contents/MacOS/$EXE"
sed -e "s/\$(EXECUTABLE_NAME)/$EXE/" -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e "s|>Zapbar<|>$APP_NAME<|g" \
    macos/PohstepRemote/Info.plist > "$APP/Contents/Info.plist"
# The iconset PNGs are already masked. iconutil only packs them. Same step for the normal and sandboxed builds.
iconutil -c icns assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp assets/zapbarTemplate.png "assets/zapbarTemplate@2x.png" "assets/zapbarTemplate@3x.png" "$APP/Contents/Resources/"
# In-app mark: the approved 128 px icon, copied as-is.
cp assets/AppIcon.iconset/icon_128x128.png "$APP/Contents/Resources/ZapbarMark.png"
if [ "${ZAPBAR_ADVANCED:-0}" = 1 ]; then
  cp Sources/TvRemoteCore/Resources/never-touch.json Sources/TvRemoteCore/Resources/cleanup-preview.json "$APP/Contents/Resources/"
fi

if [ "$SANDBOX" = 1 ]; then
  NOTICE="$(notice_file)"
  mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/Licenses"
  cp "$ADB_BINARY" "$APP/Contents/Helpers/adb"
  chmod 755 "$APP/Contents/Helpers/adb"
  cp "$NOTICE" "$APP/Contents/Resources/Licenses/adb-NOTICE.txt"
  # Sign the helper first. Do not use --deep: it would replace the helper entitlements.
  # Hardened runtime on both signatures. Entitlements stay as they are.
  codesign --force --options runtime --sign "$SIGN" --entitlements macos/PohstepRemote/adb-helper.entitlements "$APP/Contents/Helpers/adb"
  codesign --force --options runtime --sign "$SIGN" --entitlements macos/PohstepRemote/Zapbar.entitlements "$APP"
else
  codesign --force --deep --sign "$SIGN" "$APP"
fi
got="$(lipo -archs "$APP/Contents/MacOS/$EXE")"
require_archs "$APP/Contents/MacOS/$EXE" "$got"
if [ "$SANDBOX" = 1 ]; then
  require_archs "$APP/Contents/Helpers/adb" "$(lipo -archs "$APP/Contents/Helpers/adb")"
fi
echo "Built and signed ($SIGN): $APP"
echo "lipo -archs: $got"

[ "${NO_INSTALL:-0}" = 1 ] && exit 0
pkill -f "$APP_NAME.app/Contents/MacOS/$EXE" 2>/dev/null || true
sleep 1
mkdir -p "$INSTALL_DIR"; rm -rf "$INSTALL_DIR/$APP_NAME.app"
ditto "$APP" "$INSTALL_DIR/$APP_NAME.app"
touch "$INSTALL_DIR/$APP_NAME.app"
open "$INSTALL_DIR/$APP_NAME.app"
