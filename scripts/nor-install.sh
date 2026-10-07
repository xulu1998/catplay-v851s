#!/bin/sh
# Installs a built NOR image (scripts/build-nor-image.py output dir) over USB FEL with xfel.
# Usage: sh scripts/nor-install.sh <image-dir> [--from-linux] [--wipe-persist]
#   writes 0x10000-0xf00000 (loader, kernel, DTB, table, root); /persist (0xf00000-end: pairings, HomeKit
#   identity, logs) is kept unless --wipe-persist.
#   --from-linux: the box is running a bench image with its ACM shell; enter FEL by software first.
# Safeguards: full 16 MiB dump first (backups/nor-pre-install-*.bin), 0x0-0x10000 (stock Boot0)
# must match the image and is never written, full readback must equal the image, then reset and boot.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
XFEL=${XFEL:-xfel}   # https://github.com/xboot/xfel, in PATH or set XFEL=/path/to/xfel
IMG="$1/u5a-nor.bin"; [ -f "$IMG" ] || { echo "no $IMG"; exit 2; }
mkdir -p "$ROOT/backups"
TS=$(date +%Y%m%d-%H%M%S); LOG="$ROOT/backups/nor-install-$TS.log"; DUMP="$ROOT/backups/nor-pre-install-$TS.bin"
note() { echo "[host $(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
fel_ok() { perl -e 'alarm 8; exec @ARGV' "$XFEL" version 2>/dev/null | grep -q AWUSBFEX; }
acm_tty() { ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null | head -n 1; }

if [ "${2:-}" = --from-linux ]; then
  T=$(acm_tty); [ -n "$T" ] || { note "no ACM shell"; exit 3; }
  note "software FEL from Linux"
  python3 "$ROOT/tools/u5a_live.py" "$T" 5 "devmem 0x07090108 32 0x5aa5a55a; sync; devmem 0x020500a8 32 0x16aa0001" >/dev/null 2>&1
  w=0; while [ $w -lt 40 ] && ! fel_ok; do w=$((w+1)); sleep 1; done
fi
fel_ok || { note "NOT_HEALTHY_FEL"; exit 4; }
note "== dump =="
"$XFEL" spinor read 0x0 0x1000000 "$DUMP" >/dev/null || { note DUMP_FAILED; exit 5; }
head -c 65536 "$DUMP" > "$DUMP.head"; head -c 65536 "$IMG" > "$DUMP.imghead"
cmp -s "$DUMP.head" "$DUMP.imghead" || { note "0x0-0x10000 on the flash differs from the image: stop"; exit 6; }
rm -f "$DUMP.head" "$DUMP.imghead"
note "dump $DUMP"
END=0xf00000; case " $* " in *" --wipe-persist "*) END=0x1000000 ;; esac
python3 -c "import sys; d=open(sys.argv[1],'rb').read(); open(sys.argv[2],'wb').write(d[0x10000:int(sys.argv[3],16)])" "$IMG" "$1/u5a-nor-write.bin" "$END"
note "== write 0x10000-$END =="
s=$(date +%s); "$XFEL" spinor write 0x10000 "$1/u5a-nor-write.bin" >/dev/null 2>&1; note "write $(( $(date +%s) - s )) s"
"$XFEL" spinor read 0x0 0x1000000 "$1/readback.bin" >/dev/null
python3 - "$1/readback.bin" "$IMG" "$END" <<'PY' | tee -a "$LOG"
import sys
r, i, end = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read(), int(sys.argv[3], 16)
ok = r[:end] == i[:end]
print("INSTALL_VERIFIED (0x0-0x%x byte-identical%s)" % (end, ", /persist kept" if end < 0x1000000 else "") if ok else "READBACK_MISMATCH below 0x%x" % end)
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || exit 9
rm -f "$1/readback.bin"
"$XFEL" write32 0x07090108 0 >/dev/null; "$XFEL" reset >/dev/null 2>&1 || true
note "reset; the box now boots from NOR"
