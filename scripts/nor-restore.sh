#!/bin/sh
# Restores the NOR from a full 16 MiB dump (default: blobs/factory-flash.bin, the dump taken before the
# first install).
# Needs a healthy FEL (pad short if the box does not boot). Writes 0x10000-end only: stock Boot0 at
# 0x0-0x10000 is never rewritten by this project. Full readback compare afterwards.
# Usage: sh scripts/nor-restore.sh [dump.bin]
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
XFEL=${XFEL:-xfel}
SRC=${1:-$ROOT/blobs/factory-flash.bin}
[ "$(wc -c < "$SRC" | tr -d ' ')" = 16777216 ] || { echo "not a 16 MiB dump: $SRC"; exit 2; }
perl -e 'alarm 8; exec @ARGV' "$XFEL" version | grep -q AWUSBFEX || { echo "NOT_HEALTHY_FEL (short the pads)"; exit 3; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
echo "restore source: $SRC ($(shasum -a 256 "$SRC" | cut -c1-16))"
"$XFEL" spinor
"$XFEL" spinor read 0x0 0x10000 "$T/head.bin"
head -c 65536 "$SRC" > "$T/srchead.bin"
cmp -s "$T/head.bin" "$T/srchead.bin" || echo "WARNING: 0x0-0x10000 on the flash differs from the source (left untouched)"
tail -c +65537 "$SRC" > "$T/tail.bin"
"$XFEL" spinor write 0x10000 "$T/tail.bin"
"$XFEL" spinor read 0x0 0x1000000 "$T/readback.bin"
tail -c +65537 "$T/readback.bin" > "$T/rbtail.bin"
if cmp -s "$T/rbtail.bin" "$T/tail.bin"; then echo "RESTORE_VERIFIED: 0x10000-end equals the source"; else echo "RESTORE_READBACK_MISMATCH"; exit 4; fi
echo "Power-cycle the box (unplug/replug) to boot the restored firmware."
