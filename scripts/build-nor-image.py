#!/usr/bin/env python3
"""Build the 16 MiB U5A NOR image for the P5 install (docs/P5-NOR-DESIGN.md §4).

usage: build-nor-image.py <base-nor.bin> <loader-boot.img> <zImage> <rootfs.erofs> <board.dts> <dtc> <outdir>

0x000000-0x010000  copied from <base-nor.bin> unchanged (stock Boot0)
0x010000           TOC1: factory header and item table; item 'u-boot' (0x400, 0x3c000) = u5a-loader,
                   item 'dtb' kept byte for byte; add_sum recomputed; rest of the 0x80000 slot as base
0x080000           zImage                 0x460000  DTB (E28 DT, initrd-end set from the root size)
0x470000           boot table (U5AB)      0x480000  rootfs.erofs (EROFS lz4hc, mounted in place)
0xf00000-end       persist, erased (0xFF)
"""
import hashlib, json, os, struct, subprocess, sys, zlib

STAMP = 0x5F0A6C39
base_p, loader_p, zimage_p, rootfs_p, dts_p, dtc, outdir = sys.argv[1:8]
base = open(base_p, 'rb').read()
loader = open(loader_p, 'rb').read()
zimage = open(zimage_p, 'rb').read()
rootfs = open(rootfs_p, 'rb').read()
assert len(base) == 0x1000000 and len(loader) == 0x3c000

def stamp_sum(buf, off):
    b = bytearray(buf); struct.pack_into('<I', b, off, STAMP)
    return sum(struct.unpack('<%dI' % (len(b) // 4), b)) & 0xffffffff

# sanity of the base: stock Boot0 and factory TOC1 layout
assert base[4:12] == b'eGON.BT0' and stamp_sum(base[:0x9000], 12) == struct.unpack('<I', base[12:16])[0]
toc = 0x10000
assert base[toc:toc + 13] == b'sunxi-package'
valid_len = struct.unpack('<I', base[toc + 0x24:toc + 0x28])[0]
items = [(base[toc + 0x40 + i * 0x170:toc + 0x80 + i * 0x170].split(b'\0')[0],) +
         struct.unpack('<2I', base[toc + 0x80 + i * 0x170:toc + 0x88 + i * 0x170]) for i in range(2)]
assert valid_len == 0x58000 and items == [(b'u-boot', 0x400, 0x3c000), (b'dtb', 0x3c400, 0x1a5a7)], items
assert stamp_sum(base[toc:toc + valid_len], 0x14) == struct.unpack('<I', base[toc + 0x14:toc + 0x18])[0]
assert loader[4:12] == b'uboot\0\0\0' and stamp_sum(loader, 12) == struct.unpack('<I', loader[12:16])[0]

img = bytearray(b'\xff' * 0x1000000)
img[0:0x80000] = base[0:0x80000]                       # Boot0 + whole factory TOC1 slot, then overwrite
img[toc + 0x400:toc + 0x400 + 0x3c000] = loader
struct.pack_into('<I', img, toc + 0x14, stamp_sum(img[toc:toc + valid_len], 0x14))

# DTB: E28 DT with the initrd window sized to this root
INITRD = 0x43400000
assert len(rootfs) % 4096 == 0 and INITRD + len(rootfs) <= 0x43f00000
dts = open(dts_p).read()
import re
dts2 = re.sub(r'linux,initrd-end = <0x[0-9a-f]+>;', 'linux,initrd-end = <0x%x>;' % (INITRD + len(rootfs)), dts)
assert 'linux,initrd-start = <0x43400000>;' in dts2 and dts2 != dts or ('0x%x' % (INITRD + len(rootfs))) in dts
assert 'reserved-memory' not in dts2, "a reserved-memory node broke early boot (E29c)"
os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, 'board.dts'), 'w').write(dts2)
subprocess.check_call([dtc, '-q', '-I', 'dts', '-O', 'dtb', '-o', os.path.join(outdir, 'board.dtb'), os.path.join(outdir, 'board.dts')])
dtb = open(os.path.join(outdir, 'board.dtb'), 'rb').read()

layout = [("zImage", 0x080000, 0x3e0000, zimage, 0x41800000),
          ("board.dtb", 0x460000, 0x10000, dtb, 0x43000000),
          ("rootfs.erofs", 0x480000, 0xa80000, rootfs, INITRD)]
entries = []
for name, off, cap, data, dram in layout:
    assert len(data) <= cap, (name, len(data), cap)
    img[off:off + len(data)] = data
    entries.append((off, len(data), dram, zlib.crc32(data) & 0xffffffff))
table = struct.pack('<3I', 0x42413555, 1, 3) + b''.join(struct.pack('<4I', *e) for e in entries)
table += struct.pack('<I', zlib.crc32(table) & 0xffffffff)
img[0x470000:0x470000 + len(table)] = table
assert all(b == 0xff for b in img[0xf00000:])

open(os.path.join(outdir, 'u5a-nor.bin'), 'wb').write(img)
open(os.path.join(outdir, 'u5a-nor-0x10000.bin'), 'wb').write(img[0x10000:])   # what gets written
man = {"base": os.path.basename(base_p), "base_sha256": hashlib.sha256(base).hexdigest(),
       "toc1_add_sum": hex(struct.unpack('<I', img[toc + 0x14:toc + 0x18])[0]),
       "loader_head_sum": hex(struct.unpack('<I', loader[12:16])[0]),
       "images": {n: {"nor": hex(e[0]), "len": e[1], "dram": hex(e[2]), "crc32": hex(e[3])} for (n, *_), e in zip(layout, entries)},
       "u5a-nor.bin_sha256": hashlib.sha256(img).hexdigest(),
       "unchanged_0x0-0x10000": img[:0x10000] == base[:0x10000]}
json.dump(man, open(os.path.join(outdir, 'manifest.json'), 'w'), indent=1)
print(json.dumps(man, indent=1))
