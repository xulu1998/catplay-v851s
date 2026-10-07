#!/usr/bin/env python3
"""Wrap the loader code in the factory U-Boot head so stock Boot0 accepts it as the TOC1 'u-boot' item.

usage: mkimage.py <factory-nor.bin> <code.bin> <out.bin>
The first 0x640 bytes are copied from the factory u-boot item (NOR 0x10400): branch to 0x640, magic
'uboot', checksum, align 0x4000, length, run address 0x42000000, and the area Boot0 fills with DRAM
parameters. length/uboot_length are set to the padded size and the stamp checksum is recomputed
(same algorithm as Boot0's eGON and the TOC1 add_sum, verified against the factory image).
"""
import struct, sys

STAMP = 0x5F0A6C39
HEAD = 0x640

def stamp_sum(buf, off):
    b = bytearray(buf)
    struct.pack_into('<I', b, off, STAMP)
    return sum(struct.unpack('<%dI' % (len(b) // 4), b)) & 0xffffffff

nor, code_path, out = sys.argv[1:4]
pad_to = int(sys.argv[5], 0) if len(sys.argv) > 5 and sys.argv[4] == '--pad' else None
f = open(nor, 'rb').read()
uboot = f[0x10400:0x10400 + 0x3c000]
assert uboot[4:12] == b'uboot\0\0\0' and struct.unpack('<I', uboot[0:4])[0] == 0xea00018e
assert stamp_sum(uboot, 12) == struct.unpack('<I', uboot[12:16])[0], "factory head checksum"
code = open(code_path, 'rb').read()
img = bytearray(uboot[:HEAD]) + code
align = struct.unpack('<I', uboot[16:20])[0]          # 0x4000
img += b'\0' * ((-len(img)) % align)
if pad_to:                                            # keep the factory item length (0x3c000)
    assert len(img) <= pad_to
    img += b'\0' * (pad_to - len(img))
struct.pack_into('<II', img, 20, len(img), len(img))  # length, uboot_length
struct.pack_into('<I', img, 12, stamp_sum(img, 12))
assert len(img) <= 0x3c000
open(out, 'wb').write(img)
print("%s: %d bytes (code %d), checksum 0x%08x" % (out, len(img), len(code), struct.unpack('<I', img[12:16])[0]))
