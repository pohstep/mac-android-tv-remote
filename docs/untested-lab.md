# Still needs the emulator lab or a real TV

Linux `swift test` covers clean-up with a fake adb: the never-touch matcher, the undo file, the command that turns a package off, the read-back, and the automatic restore when the Home screen check fails.

These are not run here:

- `pm disable-user --user 0` and `pm enable` on a TV image, including a package the firmware reports as changed and then turns back on at boot.
- The exact text of `cmd package resolve-activity` for the Home screen on a TV image, and a set that stops answering after a change.
- Whether a short pause between packages is enough for the set to record the new state before the next one.
- China firmware versus other firmware on a real set: which packages are installed, and that nothing is selected until the user ticks them.
- Restore all when the set does not answer, then answers again later.
- A dev build (`scripts/build-dev.sh`) on a Mac, with the Advanced section collapsed and Clean up off until the switch is turned on.

Do not point this at a real set until there is a restore ready and Jim says the moment is fine. The release build (`scripts/build-local.sh`) does not include clean-up.
