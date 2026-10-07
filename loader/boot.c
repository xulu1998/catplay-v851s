/* u5a-loader boot path (docs/P5-NOR-DESIGN.md §3): read the boot table at NOR 0x470000, load the kernel,
 * DTB and EROFS root into DRAM with CRC32 checks, then hand over like launch.bin. Any failure leaves the
 * Boot0 FEL flag set and resets through the watchdog, so a bad image ends in FEL, never in a dead box.
 * Only SPI commands 0x9f and 0x03 are used: this code cannot erase or program the flash. */
#include "loader.h"

#define BOOT_TABLE_NOR 0x470000u
#define BOOT_MAGIC     0x42413555u     /* "U5AB" */
#define REPORT         0x0003a000u     /* SRAM A1, readable with devmem and after a reset */
#define WDOG           0x020500a0u
#define RTC_GPR2       0x07090108u
#define FEL_FLAG       0x5aa5a55au
#define DTB_ADDR       0x43000000u     /* r2 at hand-over (start.S) */
#define NIMG           3               /* 0 zImage, 1 DTB, 2 rootfs.erofs */

struct entry { u32 nor_off, len, dram, crc32; };
struct table { u32 magic, version, count; struct entry e[NIMG]; u32 crc32; };   /* crc32 over the bytes before it */

struct boot_report {
    u32 magic;            /* "U5AB" */
    u32 version;
    u32 stage;            /* 1 start, 2 spi, 3 table ok, 0x10+i image i loaded, 6 hand-over; 0xE0+ failure */
    u32 jedec;
    u32 gpr2_at_entry, wdog_mode_at_entry;
    u32 crc_calc[NIMG], crc_table[NIMG];
    u32 ticks_total;
    u32 done;             /* "DONE" */
};

static void fail(volatile struct boot_report *r, u32 code)
{
    r->stage = 0xE0 + code;
    W32(RTC_GPR2, FEL_FLAG);
    clean_caches();                 /* the report lives in cached SRAM: write it back before the reset */
    __asm__ volatile("dsb sy" ::: "memory");
    W32(WDOG + 0x08, 0x16aa0001);   /* SRST: immediate system reset -> Boot0 -> FEL */
    for (;;)
        ;
}

static int range_ok(u32 dram, u32 len)
{
    /* inside DRAM, and never over the running loader (0x42000000-0x42040000) */
    if (len == 0 || dram < 0x40000000u || dram + len > 0x44000000u || dram + len < dram)
        return 0;
    return dram + len <= 0x42000000u || dram >= 0x42040000u;
}

u32 loader_main(u32 cpsr, u32 sctlr)
{
    volatile struct boot_report *r = (volatile struct boot_report *)REPORT;
    (void)cpsr; (void)sctlr;
    mmu_on();
    for (u32 i = 0; i < sizeof(*r) / 4; i++)
        ((volatile u32 *)r)[i] = 0;
    r->magic = BOOT_MAGIC;
    r->version = 1;
    r->gpr2_at_entry = R32(RTC_GPR2);
    r->wdog_mode_at_entry = R32(WDOG + 0x18);
    W32(RTC_GPR2, FEL_FLAG);        /* until u5a-init clears it, any reset lands in FEL */
    wdog_arm();
    u64 t0 = ticks();
    r->stage = 1;

    spi_init();
    r->jedec = spinor_jedec_id();
    r->stage = 2;

    struct table t;
    spinor_read(BOOT_TABLE_NOR, &t, sizeof(t));
    if (t.magic != BOOT_MAGIC || t.version != 1 || t.count != NIMG)
        fail(r, 1);
    if (crc32((const u8 *)&t, sizeof(t) - 4) != t.crc32)
        fail(r, 2);
    for (u32 i = 0; i < NIMG; i++) {
        r->crc_table[i] = t.e[i].crc32;
        if (!range_ok(t.e[i].dram, t.e[i].len) || t.e[i].nor_off + t.e[i].len > 0x1000000u || t.e[i].nor_off < 0x80000u)
            fail(r, 3 + i);
    }
    if (t.e[1].dram != DTB_ADDR)
        fail(r, 6);
    r->stage = 3;

    crc32_table_init();
    for (u32 i = 0; i < NIMG; i++) {
        u32 c = 0xffffffffu;
        spinor_read_fast(t.e[i].nor_off, (void *)t.e[i].dram, t.e[i].len, &c);
        r->crc_calc[i] = c ^ 0xffffffffu;
        if (r->crc_calc[i] != t.e[i].crc32)
            fail(r, 0x10 + i);
        r->stage = 0x10 + i;
    }

    prepare_hardware();             /* USB reset + 16 s safety watchdog, as launch.bin */
    r->ticks_total = (u32)(ticks() - t0);
    r->stage = 6;
    r->done = 0x454e4f44;
    __asm__ volatile("dsb sy" ::: "memory");
    return t.e[0].dram;
}
