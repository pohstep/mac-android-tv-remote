# Changelog

## 1.1 — 2026-10-26

- Product name is Zapbar. Bundle id is `com.pohstep.tvremote`.
- Sandboxed builds can embed a local `adb` (never downloaded at runtime) and launch it with `TMPDIR` and `ADB_SERVER_SOCKET`.
- Finds TVs with Bonjour plus a small scan for Sony IP control and the experimental Xiaomi port.
- Remembers more than one TV, reconnects to the last one, and wakes it from the menu bar. A v1.0 settings file becomes the first saved TV.
- Setup is a short step-by-step flow: brand, address, debugging, pair or allow, save.
- A text field types on the TV. `⌃⌥T` opens it. Global keyboard capture stays in the non-sandbox build only.
- Experimental Xiaomi keys, app launch, and HDMI, checked against `scripts/mock-xiaomi.py`.

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
