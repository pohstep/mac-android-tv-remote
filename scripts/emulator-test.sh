#!/usr/bin/env bash
# Boots an Android TV emulator and runs the adb integration tests against it.
# Never selects a serial that isn't emulator-* or 127.0.0.1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_HOME
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$HOME/.local/share/swiftly/bin:$PATH"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

ADB="$ANDROID_HOME/platform-tools/adb"
EMU="$ANDROID_HOME/emulator/emulator"
AVD_NAME="pohstep-tv"
IMAGE="system-images;android-36;android-tv;x86_64"

if [[ ! -x "$ADB" || ! -x "$EMU" ]]; then
  echo "Installing Android SDK packages into $ANDROID_HOME"
  yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
  sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "emulator" "platforms;android-34" "build-tools;34.0.0" "$IMAGE"
fi

if ! "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" list avd | grep -q "Name: $AVD_NAME"; then
  DEVICE_FLAG=()
  if "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" list device | grep -q "id: tv_1080p"; then
    DEVICE_FLAG=(--device tv_1080p)
  fi
  echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
    -n "$AVD_NAME" -k "$IMAGE" "${DEVICE_FLAG[@]}" --force
fi

if ! "$ADB" devices | awk '/^emulator-/ && $2=="device" {found=1} END{exit !found}'; then
  # `emulator -accel-check` only asks for the API version. On some nested
  # hosts that call succeeds and KVM_CREATE_VCPU then faults, so this probe
  # actually creates a vCPU. A crash or a non-zero status means software.
  ACCEL="on"
  BOOT_TRIES=90
  if ! python3 - <<'PY'
import os, ctypes, sys
libc = ctypes.CDLL(None, use_errno=True)
try:
    fd = os.open("/dev/kvm", os.O_RDWR | os.O_CLOEXEC)
except OSError:
    sys.exit(1)
if libc.ioctl(fd, 0xAE00) != 12:  # KVM_GET_API_VERSION
    sys.exit(1)
vm = libc.ioctl(fd, 0xAE01, 0)  # KVM_CREATE_VM
if vm < 0:
    sys.exit(1)
vcpu = libc.ioctl(vm, 0xAE41, 0)  # KVM_CREATE_VCPU
sys.exit(0 if vcpu >= 0 else 1)
PY
  then
    echo "KVM cannot create a vCPU here. Booting the Android TV emulator on the software CPU."
    ACCEL="off"
    BOOT_TRIES=1200
  fi
  # Several emulated cores fight over one translator and make input injection time out.
  if [[ "$ACCEL" == "off" ]]; then
    CORES=1
    MEMORY=2048
  else
    CORES=2
    MEMORY=1536
  fi
  echo "Starting Android TV emulator (accel $ACCEL, cores $CORES)"
  CFG="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
  if [[ -f "$CFG" ]]; then
    # AVD files put spaces around "=". A downloadable quickboot snapshot
    # stalls when the host cannot reach Google's snapshot host.
    if grep -q '^hw.keyboard' "$CFG"; then
      sed -i 's/^hw.keyboard *=.*/hw.keyboard = yes/' "$CFG"
    else
      echo "hw.keyboard = yes" >> "$CFG"
    fi
    sed -i \
      -e 's/^fastboot.forceFastBoot *=.*/fastboot.forceFastBoot = no/' \
      -e 's/^fastboot.forceColdBoot *=.*/fastboot.forceColdBoot = yes/' \
      -e 's/^firstboot.bootFromDownloadableSnapshot *=.*/firstboot.bootFromDownloadableSnapshot = no/' \
      -e 's/^firstboot.bootFromLocalSnapshot *=.*/firstboot.bootFromLocalSnapshot = no/' \
      "$CFG"
  fi
  "$EMU" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -no-snapshot \
    -gpu swiftshader_indirect -accel "$ACCEL" -memory "$MEMORY" -cores "$CORES" -no-metrics \
    > /tmp/pohstep-emulator.log 2>&1 &
  echo $! > /tmp/pohstep-emulator.pid
  "$ADB" start-server >/dev/null
  "$ADB" wait-for-device
  booted=0
  for _ in $(seq 1 "$BOOT_TRIES"); do
    if [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      booted=1
      break
    fi
    sleep 2
  done
  if [[ "$booted" != "1" ]]; then
    echo "Android TV emulator did not finish booting. See /tmp/pohstep-emulator.log"
    exit 1
  fi
fi

SERIAL="$("$ADB" devices | awk '/^emulator-/ && $2=="device" {print $1; exit}')"
if [[ -z "$SERIAL" ]]; then
  echo "No Android TV emulator came up. Not touching any other device."
  exit 1
fi
echo "Using $SERIAL"

"$ADB" -s "$SERIAL" shell settings put global window_animation_scale 0 || true
"$ADB" -s "$SERIAL" shell settings put global transition_animation_scale 0 || true
"$ADB" -s "$SERIAL" shell settings put global animator_duration_scale 0 || true

cd "$ROOT"
POHSTEP_EMULATOR=1 POHSTEP_ADB="$ADB" swift test --filter EmulatorTests
