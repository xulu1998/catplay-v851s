#!/bin/sh
# Builds the kernel (zImage) from build/src/linux-7.2.7 (scripts/fetch-sources.sh) with
# kernel/linux-7.2.7-v851s.config. Output: build/linux-out/arch/arm/boot/zImage.
# Toolchain: arm-none-eabi-gcc (Homebrew on macOS; any arm-none-eabi- or arm-linux-gnueabihf- works,
# set CROSS_COMPILE). On macOS GNU make/sed/find are needed first in PATH (brew install make gnu-sed
# findutils, then add their gnubin directories).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/build/src/linux-7.2.7"
OUT="$ROOT/build/linux-out"
CROSS_COMPILE=${CROSS_COMPILE:-arm-none-eabi-}
KHOSTCFLAGS=${KHOSTCFLAGS:-}
if [ "$(uname -s)" = Darwin ] && [ -z "$KHOSTCFLAGS" ]; then
  # elf.h/byteswap.h shims for the host tools (brew install libelf)
  KHOSTCFLAGS="-I$ROOT/tools/macos-host-include -I$(brew --prefix libelf)/include"
fi
K() { make -C "$SRC" O="$OUT" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" ${KHOSTCFLAGS:+HOSTCFLAGS="$KHOSTCFLAGS"} "$@"; }

[ -d "$SRC" ] || { echo "run scripts/fetch-sources.sh first"; exit 2; }
grep -q initrd_blk "$SRC/init/Makefile" || { echo "patch 0013 not applied to $SRC"; exit 2; }
mkdir -p "$OUT"
cp "$ROOT/kernel/linux-7.2.7-v851s.config" "$OUT/.config"
K olddefconfig >/dev/null
# what the boot design depends on (docs/boot-and-flash.md)
for k in IPV6 OVERLAY_FS AF_UNIX_OOB BLK_DEV_INITRD EROFS_FS EROFS_FS_ZIP SPI_SUN6I MTD MTD_SPI_NOR MTD_OF_PARTS JFFS2_FS MTD_SPI_NOR_SWP_KEEP; do
  grep -q "^CONFIG_$k=y" "$OUT/.config" || { echo "CONFIG_$k not enabled"; exit 3; }
done
grep -q "^CONFIG_MTD_PARTITIONED_MASTER=y" "$OUT/.config" && { echo "the whole-flash MTD master must stay hidden"; exit 3; }
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)
K -j"$jobs" zImage modules > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 4; }
echo "kernel.release $(cat "$OUT/include/config/kernel.release")"
ls -la "$OUT/arch/arm/boot/zImage"
