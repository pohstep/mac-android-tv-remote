#!/bin/bash
# Dev build. Compiles clean-up into the app. The release script leaves it out.
export ZAPBAR_ADVANCED=1
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/build-local.sh" "$@"
