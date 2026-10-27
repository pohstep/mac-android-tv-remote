#!/bin/bash
# Sign Zapbar with a Developer ID, notarize it, and staple the ticket.
#
# No passwords are stored in the repo. The Apple ID stays in the keychain
# profile created by `xcrun notarytool store-credentials`.
#
#   SIGN_IDENTITY    Developer ID Application: Name (TEAMID)
#   NOTARY_PROFILE   keychain profile name for notarytool
#   VERSION          used in dist/Zapbar-<VERSION>.zip and .dmg
#   APP              existing .app; omit to build the sandboxed release
#
#   scripts/release-notarize.sh [--dry-run] [--app PATH] [--version VERSION]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ENTITLEMENTS="$ROOT/macos/PohstepRemote/Zapbar.entitlements"
HELPER_ENTITLEMENTS="$ROOT/macos/PohstepRemote/adb-helper.entitlements"

DRY_RUN=0
APP="${APP:-}"
VERSION="${VERSION:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

usage() {
  cat <<'EOF'
Usage: scripts/release-notarize.sh [--dry-run] [--app PATH] [--version VERSION]

Signs the bundled helper, then Zapbar, with a Developer ID Application
identity. Builds dist/Zapbar-<VERSION>.zip and dist/Zapbar-<VERSION>.dmg,
submits the disk image for notarization, staples the app and the disk image,
and rebuilds the zip from the stapled app.

  SIGN_IDENTITY     Developer ID Application: Name (TEAMID). Required.
  NOTARY_PROFILE    Name from: xcrun notarytool store-credentials. Required.
  VERSION           Version in the zip and dmg names. Required.
  APP               An existing Zapbar.app. If omitted, the sandboxed release
                    is built with scripts/build-local.sh.
  --dry-run         Print the commands. Do not run them.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --app)
      if [ "$#" -lt 2 ]; then
        echo "Pass the app path after --app." >&2
        exit 1
      fi
      APP="$2"
      shift 2
      ;;
    --version)
      if [ "$#" -lt 2 ]; then
        echo "Pass the version after --version." >&2
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$SIGN_IDENTITY" ]; then
  echo "Set SIGN_IDENTITY to the Developer ID Application name, for example 'Developer ID Application: Name (TEAMID)'." >&2
  echo "To see the identities on this Mac, run:" >&2
  echo "  security find-identity -v -p codesigning" >&2
  exit 1
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Ad-hoc signing cannot be notarized. Set SIGN_IDENTITY to a Developer ID Application identity." >&2
  echo "To see the identities on this Mac, run:" >&2
  echo "  security find-identity -v -p codesigning" >&2
  exit 1
fi

if [ -z "$NOTARY_PROFILE" ]; then
  echo "Set NOTARY_PROFILE to the keychain profile name from: xcrun notarytool store-credentials" >&2
  exit 1
fi

if [ -z "$VERSION" ]; then
  echo "Set VERSION, for example 1.1. The zip and disk image are named Zapbar-<VERSION>." >&2
  exit 1
fi

case "$VERSION" in
  *[!0-9A-Za-z._-]*)
    echo "VERSION may only use letters, numbers, dots, underscores, and hyphens." >&2
    exit 1
    ;;
esac

if [ ! -f "$APP_ENTITLEMENTS" ] || [ ! -f "$HELPER_ENTITLEMENTS" ]; then
  echo "The entitlements files are missing from macos/PohstepRemote." >&2
  exit 1
fi

DIST="$ROOT/dist"
ZIP="$DIST/Zapbar-${VERSION}.zip"
DMG="$DIST/Zapbar-${VERSION}.dmg"
BUILD_APP=0
if [ -z "$APP" ]; then
  APP="$DIST/Zapbar.app"
  BUILD_APP=1
fi

print_cmd() {
  local arg first
  first=1
  printf '  '
  for arg in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ' '
    fi
    first=0
    printf '%q' "$arg"
  done
  printf '\n'
}

run() {
  print_cmd "$@"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  "$@"
}

require_tools() {
  local tool
  for tool in codesign ditto hdiutil xcrun spctl security; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Zapbar needs '$tool' to sign and notarize. It is not on this Mac." >&2
      exit 1
    fi
  done
  if ! xcrun --find notarytool >/dev/null 2>&1; then
    echo "Zapbar needs 'xcrun notarytool'. Install the Xcode command line tools." >&2
    exit 1
  fi
  if ! xcrun --find stapler >/dev/null 2>&1; then
    echo "Zapbar needs 'xcrun stapler'. Install the Xcode command line tools." >&2
    exit 1
  fi
}

require_identity() {
  local found
  found="$(security find-identity -v -p codesigning 2>&1 || true)"
  if ! printf '%s\n' "$found" | grep -F "$SIGN_IDENTITY" >/dev/null; then
    echo "The signing identity was not found: $SIGN_IDENTITY" >&2
    echo "See the identities in this keychain with:" >&2
    echo "  security find-identity -v -p codesigning" >&2
    printf '%s\n' "$found" >&2
    exit 1
  fi
}

require_app() {
  if [ ! -d "$APP" ]; then
    echo "The app was not found at $APP." >&2
    exit 1
  fi
  if [ ! -f "$APP/Contents/Helpers/adb" ]; then
    echo "The app has no Contents/Helpers/adb. Build the sandboxed release so the helper is inside the app." >&2
    exit 1
  fi
}

notary_submit() {
  local file output id
  file="$1"
  print_cmd xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  # If Apple reports Invalid, the script fetches the log and stops:"
    print_cmd xcrun notarytool log "<submission-id>" --keychain-profile "$NOTARY_PROFILE"
    return 0
  fi
  output="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
  printf '%s\n' "$output"
  id="$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*id:[[:space:]]*//p' | head -n 1)"
  if printf '%s\n' "$output" | grep -q 'status: Accepted'; then
    return 0
  fi
  if printf '%s\n' "$output" | grep -q 'status: Invalid'; then
    echo "Apple rejected the notarization (Invalid)." >&2
  else
    echo "Apple did not accept the notarization." >&2
  fi
  if [ -n "$id" ]; then
    echo "Notarization log:" >&2
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  else
    echo "No submission id was returned, so the notarization log could not be fetched." >&2
  fi
  exit 1
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run. These commands would be run:"
else
  require_tools
  require_identity
fi

if [ "$BUILD_APP" -eq 1 ]; then
  run env SANDBOX=1 NO_INSTALL=1 SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT/scripts/build-local.sh"
fi

if [ "$DRY_RUN" -eq 0 ]; then
  require_app
fi

run mkdir -p "$DIST"

# Sign the helper first. --deep on the app would replace the helper entitlements.
run codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
  --entitlements "$HELPER_ENTITLEMENTS" "$APP/Contents/Helpers/adb"
run codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" "$APP"
run codesign --verify --deep --strict -vv "$APP"

run ditto -c -k --keepParent "$APP" "$ZIP"
run hdiutil create -volname Zapbar -srcfolder "$APP" -ov -format UDZO "$DMG"

# The disk image is submitted so both the image and the app inside it can be stapled.
# A zip cannot be stapled, so it is rebuilt after the app has a ticket.
notary_submit "$DMG"
run xcrun stapler staple "$APP"
run xcrun stapler staple "$DMG"
run ditto -c -k --keepParent "$APP" "$ZIP"

run spctl -a -vv -t exec "$APP"
run spctl -a -vv -t open --context context:primary-signature "$DMG"
run xcrun stapler validate "$APP"
run xcrun stapler validate "$DMG"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run finished. Would write $ZIP and $DMG."
else
  echo "Notarized Zapbar ${VERSION}: $ZIP and $DMG"
fi
