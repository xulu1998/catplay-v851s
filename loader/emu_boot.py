#!/usr/bin/env python3
"""Unicorn test of the u5a-loader boot path against a full NOR image (as Boot0 would load it).

usage: emu_boot.py <u5a-nor.bin> <outdir-with-zImage/board.dtb/rootfs.erofs>
Runs the clean image and four corrupted copies (flipped byte in each image, broken table) and checks:
clean -> kernel entry 0x41800000 with the three images byte-exact in DRAM, report stage 6;
corrupt -> GPR[2] = FEL flag and a watchdog SRST write, with the expected failure stage.
"""
import struct, sys
from unicorn import *
from unicorn.arm_const import *

nor_path, d = sys.argv[1:3]
NOR = open(nor_path, 'rb').read()
FILES = {n: open('%s/%s' % (d, n), 'rb').read() for n in ('zImage', 'board.dtb', 'rootfs.erofs')}
DRAM = {'zImage': 0x41800000, 'board.dtb': 0x43000000, 'rootfs.erofs': 0x43400000}
NOROFF = {'zImage': 0x80000, 'board.dtb': 0x460000, 'rootfs.erofs': 0x480000}

def run(nor, label):
    mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    mu.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_A7)
    mu.mem_map(0x40000000, 0x4000000)
    mu.mem_map(0x00020000, 0x20000)
    for b in (0x02000000, 0x02001000, 0x02050000, 0x04025000, 0x04100000, 0x07090000):
        mu.mem_map(b, 0x1000)
    mu.mem_write(0x42000000, nor[0x10400:0x10400 + 0x3c000])     # what Boot0 copies from the TOC1
    st = {"cs": False, "cmd": [], "addr": None, "rx": [], "tx": [], "srst": False}
    regs = {}
    def fb(tx):
        c = st["cmd"]; c.append(tx)
        if c[0] == 0x9f:
            i = len(c) - 2
            return (0x0b4018 >> (16 - 8 * i)) & 0xff if 0 <= i < 3 else 0xff
        if c[0] == 0x03:
            if len(c) <= 4:
                if len(c) == 4: st["addr"] = (c[1] << 16) | (c[2] << 8) | c[3]
                return 0xff
            b = nor[st["addr"]]; st["addr"] += 1; return b
        raise RuntimeError("cmd 0x%02x" % c[0])
    def hook(uc, access, addr, size, value, data):
        off = addr - 0x04025000
        if access == UC_MEM_WRITE:
            if off == 0x08:
                act = not (value & 0x80)
                if act and not st["cs"]: st["cmd"], st["addr"] = [], None
                st["cs"] = act
                if value & (1 << 31):
                    n = regs.get(0x30, 0); mtc = regs.get(0x34, 0)
                    assert st["cs"] and n <= 64 and len(st["tx"]) == mtc <= n, (n, mtc, len(st["tx"]))
                    st["rx"] += [fb(b) for b in st["tx"] + [0] * (n - mtc)]; st["tx"] = []; value &= ~(1 << 31)
            if off == 0x04: value &= ~(1 << 31)
            if off == 0x200: st["tx"].append(value & 0xff); return
            regs[off] = value
        else:
            if off == 0x300:
                b = [st["rx"].pop(0) for _ in range(min(size, len(st["rx"])))]
                v = sum(x << (8 * i) for i, x in enumerate(b))
            else:
                v = min(len(st["rx"]), 64) if off == 0x1c else regs.get(off, 0)
            uc.mem_write(addr, struct.pack('<I', v)[:size])
    mu.hook_add(UC_HOOK_MEM_WRITE | UC_HOOK_MEM_READ, hook, begin=0x04025000, end=0x04025fff)
    def wd(uc, access, addr, size, value, data):
        if addr == 0x020500a8 and value == 0x16aa0001:
            st["srst"] = True; uc.emu_stop()
    mu.hook_add(UC_HOOK_MEM_WRITE, wd, begin=0x020500a8, end=0x020500ab)
    tick = [0]
    def code(uc, addr, size, data):
        tick[0] += 50
        if addr == 0x41800000: uc.emu_stop(); return
        insn = struct.unpack('<I', uc.mem_read(addr, 4))[0]
        if insn & 0x0fffffff == 0x0e0e0f10: uc.reg_write(UC_ARM_REG_PC, addr + 4); return
        if insn & 0x0ff00fff == 0x0c500f0e:
            uc.reg_write(UC_ARM_REG_R0 + ((insn >> 12) & 15), tick[0] & 0xffffffff)
            uc.reg_write(UC_ARM_REG_R0 + ((insn >> 16) & 15), tick[0] >> 32)
            uc.reg_write(UC_ARM_REG_PC, addr + 4)
    mu.hook_add(UC_HOOK_CODE, code)
    mu.emu_start(0x42000000, 0x41800004, count=1_500_000_000)
    pc = mu.reg_read(UC_ARM_REG_PC)
    stage = struct.unpack('<I', mu.mem_read(0x3a008, 4))[0]
    gpr2 = struct.unpack('<I', mu.mem_read(0x07090108, 4))[0]
    exact = {n: bytes(mu.mem_read(DRAM[n], len(FILES[n]))) == FILES[n] for n in FILES}
    print("%-16s pc=0x%08x stage=0x%02x gpr2=0x%08x srst=%s r2=0x%08x dram_exact=%s"
          % (label, pc, stage, gpr2, st["srst"], mu.reg_read(UC_ARM_REG_R2), exact))
    return pc, stage, gpr2, st["srst"], exact, mu.reg_read(UC_ARM_REG_R2)

ok = True
pc, stage, gpr2, srst, exact, r2 = run(NOR, "clean")
ok &= pc == 0x41800000 and stage == 6 and all(exact.values()) and r2 == 0x43000000 and not srst
for name, want in (("zImage", 0xF0), ("board.dtb", 0xF1), ("rootfs.erofs", 0xF2)):
    bad = bytearray(NOR); bad[NOROFF[name] + len(FILES[name]) // 2] ^= 0x40
    pc, stage, gpr2, srst, _, _ = run(bytes(bad), "corrupt " + name)
    ok &= srst and gpr2 == 0x5aa5a55a and stage == want and pc != 0x41800000
bad = bytearray(NOR); bad[0x470010] ^= 1
pc, stage, gpr2, srst, _, _ = run(bytes(bad), "corrupt table")
ok &= srst and gpr2 == 0x5aa5a55a and stage == 0xE2
print("EMU_BOOT_PASS" if ok else "EMU_BOOT_FAIL")
sys.exit(0 if ok else 1)
