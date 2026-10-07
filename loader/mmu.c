/* Identity-mapped MMU with the D-cache on for the boot path: the SPI byte loop, the CRC table lookups and the
 * stores into DRAM otherwise all go uncached. 1 MiB sections: DRAM 0x40000000-0x44000000 normal write-back
 * cacheable, SRAM A1 (first MiB) normal cacheable, everything else strongly-ordered and execute-never.
 * start.S cleans the D-cache and turns MMU and caches off again before the kernel (Linux boot protocol). */
#include "loader.h"

#define TTB 0x43ffc000u                 /* 16 KiB, top of DRAM: above the root image window (ends < 0x43f00000) */

#define SEC        0x2u
#define SEC_B      (1u << 2)
#define SEC_C      (1u << 3)
#define SEC_XN     (1u << 4)
#define SEC_AP_RW  (3u << 10)
#define SEC_TEX(x) ((u32)(x) << 12)

void mmu_on(void)
{
    volatile u32 *t = (volatile u32 *)TTB;
    for (u32 i = 0; i < 4096; i++) {
        u32 base = i << 20, attr;
        if (base >= 0x40000000u && base < 0x44000000u)
            attr = SEC_TEX(1) | SEC_C | SEC_B;          /* normal, write-back write-allocate */
        else if (i == 0)
            attr = SEC_TEX(1) | SEC_C | SEC_B;          /* SRAM A1: report and CRC table */
        else
            attr = SEC_XN;                              /* strongly-ordered: MMIO */
        t[i] = base | attr | SEC_AP_RW | SEC;
    }
    __asm__ volatile(
        "dsb sy\n"
        "mov r0, #0\n"
        "mcr p15, 0, r0, c2, c0, 2\n"   /* TTBCR = 0: TTBR0 only */
        "mcr p15, 0, %0, c2, c0, 0\n"   /* TTBR0 */
        "mvn r0, #0\n"
        "mcr p15, 0, r0, c3, c0, 0\n"   /* DACR: all domains manager */
        "mov r0, #0\n"
        "mcr p15, 0, r0, c8, c7, 0\n"   /* invalidate TLBs */
        "mcr p15, 0, r0, c7, c5, 0\n"   /* invalidate I-cache */
        "dsb sy\n"
        "isb\n"
        "mrc p15, 0, r0, c1, c0, 0\n"
        "orr r0, r0, #0x1\n"            /* M */
        "orr r0, r0, #0x4\n"            /* C */
        "orr r0, r0, #0x1000\n"         /* I */
        "orr r0, r0, #0x800\n"          /* Z (branch prediction) */
        "mcr p15, 0, r0, c1, c0, 0\n"
        "isb\n"
        : : "r"(TTB) : "r0", "memory");
}
