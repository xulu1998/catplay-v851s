#!/usr/bin/env python3
"""Offline test of u5a-loader under Unicorn (Cortex-A7): SPI0 is emulated per the register usage in
spi.c / xfel's sys-spi.c, backed by a NOR dump. Runs until the loader jumps to the kernel entry, then
checks the report against artifacts/stage1/loader-e29/expected.json.

usage: emu_test.py <loader.img> <nor-dump.bin> <expected.json>
"""
import json, struct, sys
from unicorn import *
from unicorn.arm_const import *

img, nor_path, exp_path = sys.argv[1:4]
RETURN_MODE = len(sys.argv) > 4 and sys.argv[4] == "return"   # raw image at 0x42000640, returns via lr
nor = open(nor_path, 'rb').read()
JEDEC = 0xef4018                       # emulated part; the real one is read in E29

mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
mu.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_A7)
mu.mem_map(0x40000000, 0x4000000)      # 64 MiB DRAM
for base in (0x02000000, 0x02001000, 0x02050000, 0x04025000, 0x04100000, 0x07090000):
    mu.mem_map(base, 0x1000)
code = open(img, 'rb').read()
mu.mem_map(0x00020000, 0x20000)        # SRAM: FEL stack for the return-mode probe
if RETURN_MODE:
    mu.mem_write(0x42000640, code)
    mu.reg_write(UC_ARM_REG_SP, 0x0003c000)
    mu.reg_write(UC_ARM_REG_LR, 0x00030000)  # sentinel "FEL loop"
    mu.reg_write(UC_ARM_REG_R4, 0x11111111); mu.reg_write(UC_ARM_REG_R11, 0xbbbbbbbb)
else:
    mu.mem_write(0x42000000, code)

SPI = 0x04025000
st = {"cs": False, "cmd": [], "addr": None, "rx": [], "tx": [], "xfers": 0, "fifo_reads": 0}
regs = {}

def flash_byte(tx):
    """Feed one MOSI byte to the flash model, return the MISO byte."""
    c = st["cmd"]
    c.append(tx)
    if c[0] == 0x9f:
        idx = len(c) - 2
        return (JEDEC >> (16 - 8 * idx)) & 0xff if 0 <= idx < 3 else 0xff
    if c[0] == 0x03:
        if len(c) <= 4:
            if len(c) == 4:
                st["addr"] = (c[1] << 16) | (c[2] << 8) | c[3]
            return 0xff
        b = nor[st["addr"]] if st["addr"] < len(nor) else 0xff
        st["addr"] += 1
        return b
    raise RuntimeError("unexpected flash command 0x%02x" % c[0])

def spi_write(off, size, val):
    if off == 0x08:                    # TCR
        cs_active = not (val & (1 << 7))
        if cs_active and not st["cs"]:
            st["cmd"], st["addr"] = [], None
        st["cs"] = cs_active
        if val & (1 << 31):            # XCH: run the burst
            assert st["cs"], "transfer with CS inactive"
            n = regs.get(0x30, 0); mtc = regs.get(0x34, 0)
            assert n <= 64 and len(st["tx"]) == mtc <= n, (n, mtc, len(st["tx"]))
            st["rx"] += [flash_byte(b) for b in st["tx"] + [0] * (n - mtc)]
            st["tx"] = []
            st["xfers"] += 1
            val &= ~(1 << 31)
    if off == 0x04:
        val &= ~(1 << 31)              # soft reset completes at once
    if off == 0x200:
        st["tx"].append(val & 0xff)
        return
    regs[off] = val

def spi_read(off, size):
    if off == 0x1c:                    # FSR: RX count in [7:0]
        return min(len(st["rx"]), 64)
    if off == 0x300:
        st["fifo_reads"] += 1
        k = min(size, len(st["rx"]))
        b = [st["rx"].pop(0) for _ in range(k)]
        return sum(v << (8 * i) for i, v in enumerate(b))
    return regs.get(off, 0)

def hook_mem(uc, access, addr, size, value, data):
    if SPI <= addr < SPI + 0x1000:
        off = addr - SPI
        if access == UC_MEM_WRITE:
            spi_write(off, size, value)
        else:
            uc.mem_write(addr, struct.pack('<I', spi_read(off, size))[:size])

mu.hook_add(UC_HOOK_MEM_WRITE | UC_HOOK_MEM_READ, hook_mem, begin=SPI, end=SPI + 0xfff)

# The generic timer may not tick under Unicorn; emulate CNTPCT by instruction count via a code hook
# on mrrc p15,0,rX,rY,c14 (encoding 0xec5?.f0e).
tick = [0]
def hook_code(uc, addr, size, data):
    tick[0] += 50                      # crude: 50 timer ticks per instruction keeps delays short
    if addr in (0x41800000, 0x00030000):
        uc.emu_stop()
        return
    insn = struct.unpack('<I', uc.mem_read(addr, 4))[0]
    if insn & 0x0fffffff == 0x0e0e0f10:          # mcr/mcrne CNTFRQ                       # mcr CNTFRQ: secure-only, Unicorn refuses; hardware accepts (launch.bin)
        uc.reg_write(UC_ARM_REG_PC, addr + 4)
        return
    if insn & 0x0ff00fff == 0x0c500f0e:          # mrrc p15, 0, Rt, Rt2, c14
        rt, rt2 = (insn >> 12) & 0xf, (insn >> 16) & 0xf
        uc.reg_write(UC_ARM_REG_R0 + rt, tick[0] & 0xffffffff)
        uc.reg_write(UC_ARM_REG_R0 + rt2, tick[0] >> 32)
        uc.reg_write(UC_ARM_REG_PC, addr + 4)
mu.hook_add(UC_HOOK_CODE, hook_code)

try:
    mu.emu_start(0x42000640 if RETURN_MODE else 0x42000000, 0x41800000 + 4, count=400_000_000)
except UcError as e:
    print("EMU_ERROR", e, "pc=0x%08x" % mu.reg_read(UC_ARM_REG_PC)); sys.exit(1)
pc = mu.reg_read(UC_ARM_REG_PC)
print("stopped at pc=0x%08x r0=%d r1=0x%08x r2=0x%08x" % (pc, mu.reg_read(UC_ARM_REG_R0), mu.reg_read(UC_ARM_REG_R1), mu.reg_read(UC_ARM_REG_R2)))
names = ["magic","version","entry_cpsr","entry_sctlr","wdog_mode_at_entry","gpr2_at_entry","jedec",
         "boot0_stored","boot0_calc","boot0_len","toc1_stored","toc1_calc","toc1_len","toc1_items",
         "bulk_addr","bulk_len","bulk_crc32","ticks_read","ticks_crc","stage","done","fast_crc32","ticks_fast"]
w = struct.unpack('<23I', mu.mem_read(0x43f00000 if RETURN_MODE else 0x0003a000, 92))
r = dict(zip(names, w))
for n in names: print("%-20s 0x%08x" % (n, r[n]))
exp = {k: int(v, 16) for k, v in json.load(open(exp_path)).items()}
bad = [k for k in exp if r[k] != exp[k] and not (RETURN_MODE and k == "bulk_crc32")] + (["fast_crc32"] if r["fast_crc32"] != exp["bulk_crc32"] else [])
wd = dict(zip(("ctrl", "cfg", "mode"), struct.unpack('<3I', mu.mem_read(0x020500b0, 12))))
print("watchdog CTRL/CFG/MODE at hand-over: 0x%08x 0x%08x 0x%08x" % (wd["ctrl"], wd["cfg"], wd["mode"]))
print("spi bursts %d, fifo reads %d" % (st["xfers"], st["fifo_reads"]))
pc_cfg0 = struct.unpack('<I', mu.mem_read(0x02000060, 4))[0]
print("PC_CFG0 0x%08x (xfel V851 payload: PC0-PC5 function 4 -> low 24 bits 0x444444)" % pc_cfg0)
pins_ok = (pc_cfg0 & 0xffffff) == 0x444444
if RETURN_MODE:
    ok = pins_ok and pc == 0x00030000 and r["done"] == 0x454e4f44 and r["stage"] == 7 and not bad and r["jedec"] == JEDEC \
         and mu.reg_read(UC_ARM_REG_SP) == 0x0003c000 and mu.reg_read(UC_ARM_REG_R4) == 0x11111111 \
         and mu.reg_read(UC_ARM_REG_R11) == 0xbbbbbbbb and wd["mode"] == 0x16aa0000
else:
    ok = pins_ok and pc == 0x41800000 and r["done"] == 0x454e4f44 and r["stage"] == 6 and not bad and r["jedec"] == JEDEC \
         and mu.reg_read(UC_ARM_REG_R2) == 0x43000000 and mu.reg_read(UC_ARM_REG_R0) == 0 and wd["mode"] == 0x16aa00b1 and wd["cfg"] == 0x16aa0001
print("EMU_PASS" if ok else "EMU_FAIL %s" % bad)
sys.exit(0 if ok else 1)
