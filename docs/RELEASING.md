# Releasing Zapbar

Sign and notarize a release on a Mac. The Apple ID password stays in the login keychain. Do not put it in a file, a script, or the command line.

## One-time setup

1. Install a Developer ID Application certificate in the login keychain. Its name looks like `Developer ID Application: Name (TEAMID)`.

2. Confirm the certificate is visible:

```sh
security find-identity -v -p codesigning
```

3. Save a notarytool keychain profile. This asks for the Apple ID, the team ID, and an app-specific password, and stores them under the profile name:

```sh
xcrun notarytool store-credentials "zapbar-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

The password prompt belongs to notarytool. Leave it off the command line.

## Build, sign, and notarize

The sandboxed release needs a local platform-tools folder with `adb` and its `NOTICE` file. The script does not download them. See [adb-notice.md](adb-notice.md).

From the repository root:

```sh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="zapbar-notary" \
VERSION="1.1" \
scripts/release-notarize.sh
```

That builds the sandboxed release with `scripts/build-local.sh`, signs `Contents/Helpers/adb` and then Zapbar with the hardened runtime and a timestamp, writes `dist/Zapbar-1.1.zip` and `dist/Zapbar-1.1.dmg`, submits the disk image, staples the app and the disk image, and rebuilds the zip from the stapled app.

To print the commands without running them:

```sh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="zapbar-notary" \
VERSION="1.1" \
scripts/release-notarize.sh --dry-run
```

To sign an app that is already built (it must contain `Contents/Helpers/adb`):

```sh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="zapbar-notary" \
VERSION="1.1" \
scripts/release-notarize.sh --app dist/Zapbar.app
```

If Apple rejects the upload, the script prints the notarization log and stops. The zip and the disk image use the same `Zapbar-<VERSION>` names as the install note in the README.
