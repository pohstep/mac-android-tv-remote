# Changelog

## 1.1.1 — unreleased

- Send text only when the TV keyboard is actually shown. A hidden keyboard keeps the text and offers Retry. Dropped text is added to the field. An .apk dropped on the field installs. Command-modified keys reach the menu.
- Install is .apk only. A disconnected TV, and any other install error, says what to do next. The log keeps one entry per file and notes files that were skipped. A new install or a screenshot clears it.
- A screenshot can be cancelled. If the picture doesn't come back, Retry sits beside the next step. A failed save says to choose another folder and keeps the system error in the log.
- One power button. It says Turn on, Turn off, or Checking…. The menu label refreshes when the menu opens and while it stays open. Turn on tries the wake key, then Sony, then a packet on ports 9 and 7 whenever a MAC address is known, and writes the method to the log only. There is no separate switch for the packet. After sleep, one missed reading is not off. A second missed reading, or standby, is off. Xiaomi shows that power isn't supported.
- Setup, banners, and errors say what to do next. One skipped file says "isn't an .apk"; more than one says "aren't .apk." A second transfer says to wait for the current one.
- A failed login-item change shows in Settings, with Open Login Items.
- The app list comes from the leanback query.
- Turn on keeps working after the TV slept overnight. The address is learned once while the TV is connected and saved with that TV. Build 4.

## 1.1 — 2026-10-26

Release build: core setup, drop an .apk, screenshot, and the approved icon.

- Product name is Zapbar. Bundle id is `com.pohstep.tvremote`.
- Setup is a short step-by-step flow: brand, address, debugging, pair or allow, save. Several TVs are remembered. The last one reconnects on launch, and wake is in the menu bar. Release and sandbox builds leave a v1.0 settings file and the old keychain item unread. `scripts/build-dev.sh` sets `ZAPBAR_MIGRATE_V1` for that migration.
- Finds TVs with Bonjour plus a small scan for IP control and the experimental port 6095.
- A text field types on the TV. `⌃⌥T` opens it. Global keyboard capture stays in the non-sandbox build only.
- Drop an .apk on the menu bar icon or the panel, or press Choose .apk…, to install it. Other files are refused. The result is one plain sentence, with the original message kept underneath.
- Screenshot copies the picture to the clipboard or saves it. A black picture is kept, with a note that the TV may block protected video. Save asks for a folder and a name. If that save fails, choose another folder and press Save again.
- The app icon and the menu bar glyph are the approved zap mark. The panel header and the first setup step show the Zapbar wordmark.
- Try demo TV shows a connected panel when no TV is found, and from Settings. Key presses, an app install, and a screenshot stay on this Mac. Demo mode is not saved.
- Transfers run one at a time. Cancel stops an install. A sandboxed build can embed a local helper (never downloaded at runtime), uses its own port, and is signed with the hardened runtime.
- The Swift package asks for tools version 5.8.

Built, and left out of the release app until Jim says go:

- Clean-up with undo sits behind an Advanced section and the compile flag `ZAPBAR_ADVANCED`. `scripts/build-local.sh` leaves the flag off, so the release app has no clean-up code. `scripts/build-dev.sh` turns it on. `swift test` still covers it.

Experimental, and included in the release build:

- Port 6095 keys, app launch, and HDMI, checked against `scripts/mock-xiaomi.py`. It cannot type and cannot power the set on.

## 1.0.1 — 2026-10-26

- Arrow keys are now four large wedge-shaped click zones around the OK button, so you no longer have to hit the small glyph.

## 1.0 — 2026-10-21

First release.

- Menu bar remote: D-pad, OK, Back, Home, volume slider and steps, mute, play/pause, previous/next.
- Apps from the TV (Sony `getApplicationList`) with real icons, 12 pinned plus **More apps…**, launched with `setActiveApp` (adb fallback).
- Input picker with the TV's own names ("HDMI 1 — Apple TV").
- Power on that actually wakes the TV: Sony `setPowerStatus`, then Wake-on-LAN, then adb `KEYCODE_WAKEUP`, then a status re-check. Power off needs a second click.
- Keyboard as remote: ⌃⌥K toggles, ⌃⌥⌘K always turns it off. Arrows, Return, Esc (Back), Backspace (Delete), and typed text (adb `input text`, batched). Keyboard only; the mouse and trackpad stay with the Mac.
- Pre-shared key stored in the macOS keychain, never in settings or logs. Typed characters are never logged.
- Builds with `swiftc` alone; no Xcode needed.
