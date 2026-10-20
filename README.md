<p align="center"><img src="docs/icon.png" width="128" alt="Mac Android TV Remote icon"></p>

# Mac Android TV Remote

A macOS menu bar remote for Sony Bravia / Android TV: D-pad, apps, inputs, volume, power, and your Mac keyboard as the remote.

![Panel](docs/screenshots/panel.png)
<!-- Screenshot placeholders: docs/screenshots/panel.png, docs/screenshots/apps-expanded.png, docs/screenshots/menubar.png -->

## Features

- **D-pad, OK, Back, Home**, play/pause, previous/next.
- **Volume** slider, steps and mute.
- **Apps** read from the TV (Sony `getApplicationList`) with their real icons. 12 are pinned; **More apps…** expands the panel to show the rest. Launch uses Sony `setActiveApp`, with adb as a fallback.
- **Inputs** with the TV's own names, e.g. "HDMI 1 — Apple TV".
- **Power on that works from standby**: Sony `setPowerStatus` → Wake-on-LAN → adb `KEYCODE_WAKEUP`, then it re-checks the power status. Power off asks for a second click.
- **Keyboard as remote**: press **⌃⌥K** to toggle; **⌃⌥⌘K** always turns it off. Arrows are the D-pad, Return is OK, Esc is Back, Backspace deletes, and anything you type goes into the TV's search or text field (adb `input text`, batched so it feels quick). Only the keyboard is captured; the mouse and trackpad stay with your Mac. ⌘ shortcuts still go to the Mac.

## Requirements

- macOS 13 Ventura or later (Intel or Apple silicon).
- A Sony Bravia (Google TV / Android TV) with **IP control** and a **pre-shared key**.
- Optional, but recommended: [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`) with network debugging on the TV. It's needed for typing and for waking the TV when Remote Start is off.

## Setup

### On the TV

1. **Settings → Network & Internet → Home network → IP control**
   - **Authentication**: *Normal and Pre-Shared Key*
   - **Pre-Shared Key**: choose a key
   - **Simple IP control**: optional
2. **Settings → Network & Internet → Remote Start**: **On**. This lets the TV wake from standby over the network. On some models it's under **Settings → System → Power & Energy**.
3. Optional (adb): **Settings → System → About**, then press **Build** 7 times. Then go to **Settings → System → Developer options** and turn on **USB debugging** / **Network debugging**. Accept the prompt the first time your Mac connects.

### On the Mac

1. Open the app. It lives in the menu bar only and has no Dock icon.
2. Right-click the menu bar icon → **Settings…** (⌘,). Enter the TV's IP address or hostname, the pre-shared key and, optionally, the adb path and the TV's MAC address for Wake-on-LAN.
3. The pre-shared key is stored in your **login keychain**. The first time, macOS asks to let the app use it: enter your Mac password and click **Always Allow**.
4. For keyboard-as-remote, grant **System Settings → Privacy & Security → Accessibility** to the app, then quit and reopen it.

## First launch (unsigned app)

The app is not signed with an Apple developer account, so macOS blocks it the first time. Allow it once:

- **macOS 13 or 14:** in Applications, right-click **Pohstep Remote**, choose **Open**, then **Open** again.
- **macOS 15 or newer:** try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
- **Or, in Terminal:**

  ```sh
  xattr -dr com.apple.quarantine "/Applications/Pohstep Remote.app"
  ```

## Build from source

No Xcode needed: the Command Line Tools (`swiftc`) are enough.

```sh
git clone https://github.com/pohstep/mac-android-tv-remote.git
cd mac-android-tv-remote
scripts/build-local.sh            # builds, signs, installs to ~/Applications and launches
```

Options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `SIGN_IDENTITY` | `-` (ad-hoc) | codesign identity. A stable self-signed identity keeps the Accessibility grant across rebuilds. |
| `APP_NAME` | `Mac Android TV Remote` | App bundle name |
| `BUNDLE_ID` | `app.pohstep.remote` | Bundle identifier |
| `INSTALL_DIR` | `~/Applications` | Install location |
| `NO_INSTALL=1` | – | Build and sign only |

CI: a GitHub Actions workflow is included as `docs/ci/build.yml.example`. To enable it, copy it to `.github/workflows/build.yml`.

> With ad-hoc or self-signed builds (no Apple Team ID), macOS ties keychain access to each build's hash. So after every rebuild, the keychain asks once more; click **Always Allow**.

## Privacy

Everything stays on your local network. The app talks only to your TV: Sony REST/IRCC over HTTP, adb on port 5555 and Wake-on-LAN over UDP. There's no analytics, telemetry or cloud. The pre-shared key lives in the macOS keychain, and typed characters are never logged.

## License

[MIT](LICENSE) © pohstep
