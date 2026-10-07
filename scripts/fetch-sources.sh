#!/bin/sh
# Downloads the pinned upstream sources into build/src/ (ignored by git) and applies kernel/patches-*.
# Safe to re-run: a source tree that already exists is left alone (delete it to start over).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/build/src"
mkdir -p "$SRC"

LINUX=linux-7.2.7
RTL_URL=https://github.com/newbie-461/RTL8733BS_WiFi_linux_v5.14.1.1-46.git
RTL_REV=4719bf994bc4
CATPLAY_URL=https://github.com/catplay-labs/catplay.git
CATPLAY_REV=dbb3ebbcde8a

apply() {   # apply <dir> <patch>...
  d=$1; shift
  for p in "$@"; do echo "  $(basename "$p")"; patch -d "$d" -p1 -s --no-backup-if-mismatch < "$p"; done
}

if [ ! -d "$SRC/$LINUX" ]; then
  echo "== $LINUX"
  [ -f "$SRC/$LINUX.tar.xz" ] || curl -fL -o "$SRC/$LINUX.tar.xz" "https://cdn.kernel.org/pub/linux/kernel/v7.x/$LINUX.tar.xz"
  tar -xf "$SRC/$LINUX.tar.xz" -C "$SRC"
  apply "$SRC/$LINUX" "$ROOT"/kernel/patches-linux-7.2.7/*.patch
fi

if [ ! -d "$SRC/rtl8733bs" ]; then
  echo "== rtl8733bs ($RTL_REV)"
  git clone -q "$RTL_URL" "$SRC/rtl8733bs"
  git -C "$SRC/rtl8733bs" checkout -q "$RTL_REV"
  apply "$SRC/rtl8733bs" "$ROOT"/kernel/patches-rtl8733bs/*.patch
fi

if [ ! -d "$SRC/catplay" ]; then
  echo "== catplay ($CATPLAY_REV)"
  git clone -q "$CATPLAY_URL" "$SRC/catplay"
  git -C "$SRC/catplay" checkout -q "$CATPLAY_REV"
fi
if [ ! -d "$SRC/g_iphone" ]; then
  echo "== g_iphone (from catplay)"
  cp -R "$SRC/catplay/usb/catplay_iap2_usb_host/g_iphone" "$SRC/g_iphone"
  apply "$SRC/g_iphone" "$ROOT"/kernel/patches-g_iphone/*.patch
fi
echo "sources ready in $SRC"
