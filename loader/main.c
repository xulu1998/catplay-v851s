/* u5a-loader. MODE_PROBE (E29): read-only checks against the factory NOR, report at REPORT_DRAM (return mode) or REPORT_SRAM (boot path),
 * then boot the FEL-staged kernel at 0x41800000. The NOR is only read (0x9f, 0x03); nothing here
 * can erase or program it. */
#include "loader.h"

#define REPORT_DRAM   0x43f00000u     /* return-to-FEL probe: read back with `xfel read` */
#define REPORT_SRAM   0x0003a000u     /* boot path: SRAM A1, unused by Linux, read with devmem. A no-map
                                         reserved-memory node for a DRAM page broke early boot (E29c S2). */
#define BUF           0x40100000u     /* scratch, overwritten later by the kernel decompressor */
#define KERNEL_ENTRY  0x41800000u
#define STAMP         0x5f0a6c39u
#define WDOG          0x020500a0u
#define RTC_GPR2      0x07090108u

struct report {
    u32 magic;            /* 'U5AL' */
    u32 version;
    u32 entry_cpsr, entry_sctlr;
    u32 wdog_mode_at_entry, gpr2_at_entry;
    u32 jedec;
    u32 boot0_stored, boot0_calc, boot0_len;
    u32 toc1_stored, toc1_calc, toc1_len, toc1_items;
    u32 bulk_addr, bulk_len, bulk_crc32;
    u32 ticks_read, ticks_crc;  /* 24 MHz */
    u32 stage;                  /* last step reached */
    u32 done;                   /* 'DONE' */
    u32 fast_crc32, ticks_fast; /* same 4 MiB with spinor_read_fast (rx-only, word FIFO reads, fused CRC) */
};

u64 ticks(void)
{
    u32 lo, hi;
    __asm__ volatile("mrrc p15, 0, %0, %1, c14" : "=r"(lo), "=r"(hi));
    return ((u64)hi << 32) | lo;
}

static void delay_ms(u32 ms)
{
    u64 end = ticks() + (u64)ms * 24000u;
    while (ticks() < end)
        ;
}

void wdog_arm(void)
{
    W32(WDOG + 0x14, 0x16aa0001);   /* CFG: whole-system reset */
    W32(WDOG + 0x18, 0x16aa00b1);   /* MODE: interval 0xb (16 s), enable */
    W32(WDOG + 0x10, 0x14af);       /* CTRL: key + restart */
}

void wdog_feed(void)
{
    W32(WDOG + 0x10, 0x14af);
}

static u32 stamp_sum(u32 base, u32 len, u32 sum_off)
{
    u32 s = 0;
    for (u32 i = 0; i < len; i += 4)
        s += (i == sum_off) ? STAMP : R32(base + i);
    return s;
}

void crc32_table_init(void)
{
    u32 *crc_table = (u32 *)CRC_TABLE_SRAM;
    for (u32 n = 0; n < 256; n++) {
        u32 c = n;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1;
        crc_table[n] = c;
    }
}

u32 crc32(const u8 *p, u32 len)
{
    const u32 *crc_table = (const u32 *)CRC_TABLE_SRAM;
    if (crc_table[1] != 0x77073096u)
        crc32_table_init();
    u32 c = 0xffffffffu;
    while (len--) {
        c = crc_table[(c ^ *p++) & 0xff] ^ (c >> 8);
        if (!(len & 0xffff))
            wdog_feed();
    }
    return c ^ 0xffffffffu;
}

/* launch.bin prepare_hardware (E20-E28): drop the FEL MUSB session, put USB in reset, and arm the
 * 16 s safety watchdog that u5a-init disarms once the debug gadget is configured. */
void prepare_hardware(void)
{
    R8(0x04100040) &= ~0x40u;
    W32(0x04100048, 0);
    W8(0x04100050, 0);
    W8(0x04100041, 0);
    __asm__ volatile("dsb sy" ::: "memory");
    delay_ms(250);
    W32(0x02001a8c, R32(0x02001a8c) & ~((1u << 24) | (1u << 20) | (1u << 16)));
    W32(0x02001a70, R32(0x02001a70) & ~(1u << 30));
    __asm__ volatile("dsb sy" ::: "memory");
    delay_ms(10);
    W32(0x02001a8c, R32(0x02001a8c) & ~((1u << 8) | (1u << 4) | 1u));
    W32(0x02001a70, R32(0x02001a70) & ~(1u << 31));
    W32(WDOG + 0x14, 0x16aa0001);   /* CFG: whole-system reset */
    W32(WDOG + 0x10, 0x14af);       /* CTRL: key + restart */
    W32(WDOG + 0x18, 0x16aa00b1);   /* MODE: interval 0xb (16 s), enable */
}

static void probe(volatile struct report *r, u32 cpsr, u32 sctlr)
{
    for (u32 i = 0; i < sizeof(*r) / 4; i++)
        ((volatile u32 *)r)[i] = 0;
    r->magic = 0x4c413555;          /* "U5AL" */
    r->version = 1;
    r->entry_cpsr = cpsr;
    r->entry_sctlr = sctlr;
    r->wdog_mode_at_entry = R32(WDOG + 0x18);
    r->gpr2_at_entry = R32(RTC_GPR2);
    wdog_arm();                     /* 16 s system reset, fed during the reads: a hang resets the board */
    r->stage = 1;

    spi_init();
    r->stage = 0x11;                /* SPI controller up */
    r->jedec = spinor_jedec_id();
    r->stage = 2;

    spinor_read(0x0, (void *)BUF, 0x9000);
    r->boot0_stored = R32(BUF + 12);
    r->boot0_len = R32(BUF + 16);
    r->boot0_calc = (r->boot0_len == 0x9000) ? stamp_sum(BUF, 0x9000, 12) : 0;
    r->stage = 3;

    spinor_read(0x10000, (void *)BUF, 0x40);
    r->toc1_stored = R32(BUF + 0x14);
    r->toc1_items = R32(BUF + 0x20);
    r->toc1_len = R32(BUF + 0x24);
    if (r->toc1_len >= 0x40 && r->toc1_len <= 0x70000) {
        spinor_read(0x10000, (void *)BUF, r->toc1_len);
        r->toc1_calc = stamp_sum(BUF, r->toc1_len, 0x14);
    }
    r->stage = 4;

    r->bulk_addr = 0x480000;
    r->bulk_len = 0x400000;
#ifndef PROBE_FAST_ONLY
    u64 t0 = ticks();
    spinor_read(r->bulk_addr, (void *)BUF, r->bulk_len);
    u64 t1 = ticks();
    r->bulk_crc32 = crc32((const u8 *)BUF, r->bulk_len);
    u64 t2 = ticks();
    r->ticks_read = (u32)(t1 - t0);
    r->ticks_crc = (u32)(t2 - t1);
#endif
    crc32_table_init();
    u32 c = 0xffffffffu;
    u64 t3 = ticks();
    spinor_read_fast(r->bulk_addr, (void *)(BUF + 0x400000), r->bulk_len, &c);
    r->ticks_fast = (u32)(ticks() - t3);
    r->fast_crc32 = c ^ 0xffffffffu;
    r->stage = 5;
}

#ifndef MODE_BOOT
u32 loader_main(u32 cpsr, u32 sctlr)
{
    volatile struct report *r = (volatile struct report *)REPORT_SRAM;
    probe(r, cpsr, sctlr);
    prepare_hardware();
    r->stage = 6;
    r->done = 0x454e4f44;           /* "DONE" */
    __asm__ volatile("dsb sy" ::: "memory");
    return KERNEL_ENTRY;
}
#endif

/* Return-to-FEL variant: same checks, no hand-over; the watchdog stays off. */
void probe_return_main(u32 cpsr, u32 sctlr)
{
    volatile struct report *r = (volatile struct report *)REPORT_DRAM;
    probe(r, cpsr, sctlr);
    W32(WDOG + 0x18, 0x16aa0000);   /* back to FEL: no watchdog left running */
    r->stage = 7;
    r->done = 0x454e4f44;
    __asm__ volatile("dsb sy" ::: "memory");
}
