#!/bin/sh
# Assembles the flash images from the parts:
#   loader:  loader/ (make), with the factory U-Boot header from blobs/factory-flash.bin
#   kernel:  build/linux-out/arch/arm/boot/zImage (scripts/build-kernel.sh)
#   root:    the EROFS image from Yocto (u5a-e28-image-v851s-rtl8733bs.rootfs.erofs-lz4hc)
# Output: out/bench/ and out/car/ (u5a-nor.bin + manifest; install with scripts/nor-install.sh) and
#         out/u5a-ota-<mode>-<version>.bin (upload on the settings page, Firmware update).
# Usage: sh scripts/build-images.sh <rootfs.erofs> [version-text]
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROOTFS=${1:?usage: build-images.sh <rootfs.erofs> [version-text]}
VER=${2:-$(date +%Y%m%d%H%M)}
BASE="$ROOT/blobs/factory-flash.bin"
ZIMAGE=${ZIMAGE:-$ROOT/build/linux-out/arch/arm/boot/zImage}
DTC=${DTC:-dtc}
[ -f "$BASE" ] || { echo "missing $BASE (blobs/README.md)"; exit 2; }
[ -f "$ZIMAGE" ] || { echo "missing $ZIMAGE (scripts/build-kernel.sh)"; exit 2; }
make -s -C "$ROOT/loader" FACTORY="$BASE" u5a-loader-boot.img
for m in bench car; do
  python3 "$ROOT/scripts/build-nor-image.py" "$BASE" "$ROOT/loader/u5a-loader-boot.img" "$ZIMAGE" "$ROOTFS" \
    "$ROOT/kernel/dts/board-$m.dts" "$DTC" "$ROOT/out/$m" > /dev/null
  python3 "$ROOT/scripts/make-ota.py" "$ROOT/out/$m/u5a-nor.bin" "$m $VER" "$ROOT/out/u5a-ota-$m-$VER.bin"
done
grep -h '"u5a-nor.bin_sha256"' "$ROOT"/out/*/manifest.json
