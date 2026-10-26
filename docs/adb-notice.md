# adb license notice

`adb` is part of platform-tools and is licensed under the Apache License, Version 2.0. The copyright notice and the NOTICE file that ships beside the binary have to travel with it.

Zapbar does not download `adb`, or any other code, while it is running. A sandboxed build copies a binary you already have on the build machine into `Contents/Helpers/adb`.

## What to put next to the binary

Point `PLATFORM_TOOLS` (or `ADB_BINARY`) at a local platform-tools directory. That directory must contain:

- `adb` (the executable for this Mac)
- `NOTICE.txt` or `NOTICE` (the Apache-2.0 notice from the same platform-tools drop)

`scripts/build-local.sh` refuses a `SANDBOX=1` build when either file is missing. It copies the notice to `Contents/Resources/Licenses/adb-NOTICE.txt` inside the app bundle. Do not commit the binary or the notice snapshot; both stay on the build machine. `platform-tools/` is gitignored.

The notice file from platform-tools names the Android Open Source Project as the copyright holder and includes the Apache License 2.0 text. Keep that file intact. Do not replace it with a summary.
