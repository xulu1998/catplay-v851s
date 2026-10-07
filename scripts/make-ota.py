#!/usr/bin/env python3
"""Make a U5A Wi-Fi update bundle from a built NOR image (scripts/build-nor-image.py output).

usage: make-ota.py <u5a-nor.bin> <version-text> <out.bin>
Payload = NOR bytes 0x80000 .. end of the root image (rounded to 4 KiB): zImage, DTB, boot table, root.
The box's update CGI checks magic, length, the boot table at payload offset 0x3f0000 and the SHA-256,
then writes the payload to the u5a-system partition (NOR 0x80000) with flashcp.
"""
import hashlib, struct, sys
nor, version, out = sys.argv[1], sys.argv[2].encode(), sys.argv[3]
img = open(nor, 'rb').read()
assert len(img) == 0x1000000
t = img[0x470000:0x470040]
magic, ver, count = struct.unpack('<3I', t[:12])
assert magic == 0x42413555 and count == 3, "no boot table"
ends = [struct.unpack('<4I', t[12 + 16 * i:28 + 16 * i])[0] + struct.unpack('<4I', t[12 + 16 * i:28 + 16 * i])[1] for i in range(3)]
end = (max(ends) + 0xfff) & ~0xfff
assert end <= 0xf00000
payload = img[0x80000:end]
assert len(version) <= 32
hdr = b'U5AOTA01' + struct.pack('<II', len(payload), 0) + version.ljust(32, b'\0') + hashlib.sha256(payload).digest()
assert len(hdr) == 80
open(out, 'wb').write(hdr + payload)
print("%s: %d bytes payload (NOR 0x80000-0x%x), sha256 %s" % (out, len(payload), end, hashlib.sha256(payload).hexdigest()))
