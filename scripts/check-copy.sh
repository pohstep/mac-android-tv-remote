#!/bin/sh
# Fails when source text contains a blocked product name.
# The names are built from pieces so this file does not contain them.
set -eu
cd "$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

latin=$(printf '%s%s' 'Sca' 'pe')
# U+7EFD U+80DC, written as UTF-8 bytes so the characters are not in this file.
han=$(printf '\347\273\275\350\203\234')

# Skip git metadata, SwiftPM output (its generated headers contain unrelated
# compiler words), and picture bytes. Licence files are skipped because a
# vendored notice can contain an unrelated word with the same letters.
if find . \
  -path './.git' -prune -o \
  -path './.build' -prune -o \
  -path './.swiftpm' -prune -o \
  -type f \
  ! -name 'LICENSE' ! -name 'LICENSE.*' ! -name 'NOTICE' ! -name 'NOTICE.*' ! -name 'COPYING' ! -name 'COPYING.*' \
  ! -name '*.png' ! -name '*.icns' ! -name '*.pdf' \
  -print0 |
  xargs -0 grep -I -n -i -F -e "$latin" -e "$han"
then
  exit 1
fi
exit 0
