# Changelog

## 1.0 — 2026-10-21

First release.

- Menu bar remote: D-pad, OK, Back, Home, volume slider and steps, mute, play/pause, previous/next.
- Apps from the TV (Sony `getApplicationList`) with real icons, 12 pinned plus **More apps…**, launched with `setActiveApp` (adb fallback).
- Input picker with the TV's own names ("HDMI 1 — Apple TV").
- Power on that actually wakes the TV: Sony `setPowerStatus`, then Wake-on-LAN, then adb `KEYCODE_WAKEUP`, then a status re-check. Power off needs a second click.
- Keyboard as remote: ⌃⌥K toggles, ⌃⌥⌘K always turns it off. Arrows, Return, Esc (Back), Backspace (Delete), and typed text (adb `input text`, batched). Keyboard only; the mouse and trackpad stay with the Mac.
- Pre-shared key stored in the macOS keychain, never in settings or logs. Typed characters are never logged.
- Builds with `swiftc` alone; no Xcode needed.
