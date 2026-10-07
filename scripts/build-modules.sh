#!/bin/sh
# Builds the modules the image needs against build/linux-out (scripts/build-kernel.sh first) and collects
# them, stripped of debug info, in build/modules/ (the Yocto recipe u5a-bench installs them from there):
#   in-tree:     crc-ccitt, hci_uart, btrtl (Bluetooth H5 + RTL8733BS)
#   8733bs.ko:   build/src/rtl8733bs (CONFIG_BR_EXT=n)
#   g_iphone.ko, iap2_char.ko, iap2_scan.ko: build/src/g_iphone (CatPlay's iPhone USB gadget)
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/build/linux-out"
DST="$ROOT/build/modules"
CROSS_COMPILE=${CROSS_COMPILE:-arm-none-eabi-}
M() { make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" -C "$OUT" "$@"; }

grep -q "^CONFIG_IPV6=y" "$OUT/.config" 2>/dev/null || { echo "run scripts/build-kernel.sh first"; exit 2; }
rm -rf "$DST"; mkdir -p "$DST"
# The driver Makefile must be the entry point (it sets the objects from its own directory).
make -C "$ROOT/build/src/rtl8733bs" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" KSRC="$OUT" \
  M="$ROOT/build/src/rtl8733bs" CONFIG_BR_EXT=n -j8 modules > "$DST/8733bs.log" 2>&1 || { tail -30 "$DST/8733bs.log"; exit 3; }
M M="$ROOT/build/src/g_iphone" -j8 modules > "$DST/g_iphone.log" 2>&1 || { tail -30 "$DST/g_iphone.log"; exit 4; }

for f in lib/crc/crc-ccitt drivers/bluetooth/btrtl drivers/bluetooth/hci_uart; do cp "$OUT/$f.ko" "$DST/"; done
cp "$ROOT/build/src/rtl8733bs/8733bs.ko" "$DST/"
for m in iap2_char iap2_scan g_iphone; do cp "$ROOT/build/src/g_iphone/$m.ko" "$DST/"; done
for k in "$DST"/*.ko; do "${CROSS_COMPILE}strip" --strip-debug "$k"; done

want=$(cat "$OUT/include/config/kernel.release")
for k in "$DST"/*.ko; do
  vm=$("${CROSS_COMPILE}strings" "$k" | grep -m1 '^vermagic=' | cut -d= -f2 | cut -d' ' -f1)
  [ "$vm" = "$want" ] || { echo "VERMAGIC_MISMATCH $(basename "$k") $vm != $want"; exit 5; }
done
(cd "$DST" && ls -la *.ko)
