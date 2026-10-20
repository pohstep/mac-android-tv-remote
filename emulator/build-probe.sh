#!/usr/bin/env bash
# Builds the tiny input probe APK with the Android SDK command-line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/input-probe"
OUT="$SRC/build"
ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
ANDROID_JAR="$ANDROID_HOME/platforms/android-34/android.jar"
BUILD_TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"

mkdir -p "$OUT/classes"
rm -rf "$OUT/classes"/*
find "$SRC" -name '*.java' -print0 | xargs -0 javac -source 8 -target 8 -classpath "$ANDROID_JAR" -d "$OUT/classes"

CLASS_FILES=()
while IFS= read -r file; do
  CLASS_FILES+=("$file")
done < <(find "$OUT/classes" -name '*.class')

"$BUILD_TOOLS/d8" --min-api 21 --lib "$ANDROID_JAR" --output "$OUT" "${CLASS_FILES[@]}"
"$BUILD_TOOLS/aapt" package -f -M "$SRC/AndroidManifest.xml" -I "$ANDROID_JAR" -F "$OUT/probe-unsigned.apk"
(
  cd "$OUT"
  "$BUILD_TOOLS/aapt" add -f probe-unsigned.apk classes.dex >/dev/null
  "$BUILD_TOOLS/zipalign" -f 4 probe-unsigned.apk probe-aligned.apk
)

if [[ ! -f "$OUT/debug.keystore" ]]; then
  keytool -genkeypair -keystore "$OUT/debug.keystore" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=pohstep" -keyalg RSA -keysize 2048 -validity 10000
fi
"$BUILD_TOOLS/apksigner" sign --ks "$OUT/debug.keystore" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/probe.apk" "$OUT/probe-aligned.apk"
echo "built $OUT/probe.apk"
