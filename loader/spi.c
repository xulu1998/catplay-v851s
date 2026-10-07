/* SPI0 + SPI NOR read for the V851S. Register sequence from xfel (MIT, Jianjun Jiang): the CCU and
 * SPI controller part is the same as payloads/r528_t113/spi/source/sys-spi.c, but the pins are the
 * V851 ones from the binary payload in chips/v851_v853.c, which is what `xfel spinor` runs on this
 * board: PC0-PC5 function 4 (E29b found the T113 PC2-PC5 function 2 reads all zeros here).
 * SPI0 clock pll-periph0 / 6, CCR 0x1000. */
#include "loader.h"

#define SPI0      0x04025000u
#define SPI_GCR   0x04
#define SPI_TCR   0x08
#define SPI_FCR   0x18
#define SPI_FSR   0x1c
#define SPI_CCR   0x24
#define SPI_MBC   0x30
#define SPI_MTC   0x34
#define SPI_BCC   0x38
#define SPI_TXD   0x200
#define SPI_RXD   0x300

static void setbits(u32 a, u32 clr, u32 set) { W32(a, (R32(a) & ~clr) | set); }

void spi_init(void)
{
    /* Boot0 leaves SPI0 configured for its own (DMA) reads; under FEL it is at reset state. Put the
     * controller through a full CCU reset first so both cases start from the same state (E30b hung here). */
    setbits(0x0200196c, (1u << 16) | (1u << 0), 0);   /* assert reset, bus gate off */
    setbits(0x02001940, 1u << 31, 0);                 /* module clock off */
    for (volatile int i = 0; i < 1000; i++)
        ;
    for (int pin = 0; pin <= 5; pin++)
        setbits(0x02000060, 0xfu << (pin * 4), 0x4u << (pin * 4));
    setbits(0x0200196c, 0, 1u << 16);          /* deassert spi0 reset */
    setbits(0x02001940, 0, 1u << 31);          /* spi0 module clock gate */
    setbits(0x0200196c, 0, 1u << 0);           /* spi0 bus gate */
    setbits(0x02001940, 0x3u << 24, 0x1u << 24); /* pll-periph0 */
    setbits(0x02001940, 0x3u << 8, 0);         /* pre-divide 1 */
    setbits(0x02001940, 0xfu, 6 - 1);          /* divide 6 */
    W32(SPI0 + SPI_CCR, 0x1000);
    setbits(SPI0 + SPI_GCR, 0, (1u << 31) | (1u << 7) | (1u << 1) | (1u << 0));
    while (R32(SPI0 + SPI_GCR) & (1u << 31))
        ;
    setbits(SPI0 + SPI_TCR, 0x3u, (1u << 6) | (1u << 2));
    W32(SPI0 + SPI_FCR, (1u << 31) | (1u << 15));     /* reset both FIFOs, no DMA requests */
}

static void cs(int active)
{
    setbits(SPI0 + SPI_TCR, (0x3u << 4) | (1u << 7), active ? 0 : (1u << 7));
}

/* Full-duplex transfer of up to 64 bytes per burst, as xfel. */
static void xfer(const u8 *tx, u8 *rx, u32 len)
{
    while (len) {
        u32 n = len > 64 ? 64 : len;
        W32(SPI0 + SPI_MBC, n);
        W32(SPI0 + SPI_MTC, n);
        W32(SPI0 + SPI_BCC, n);
        for (u32 i = 0; i < n; i++)
            W8(SPI0 + SPI_TXD, tx ? tx[i] : 0xff);
        W32(SPI0 + SPI_TCR, R32(SPI0 + SPI_TCR) | (1u << 31));
        while (R32(SPI0 + SPI_TCR) & (1u << 31))
            ;
        while ((R32(SPI0 + SPI_FSR) & 0xff) < n)
            ;
        for (u32 i = 0; i < n; i++) {
            u8 v = R8(SPI0 + SPI_RXD);
            if (rx)
                rx[i] = v;
        }
        if (tx)
            tx += n;
        if (rx)
            rx += n;
        len -= n;
    }
}

u32 spinor_jedec_id(void)
{
    u8 cmd = 0x9f, id[3];
    cs(1);
    xfer(&cmd, 0, 1);
    xfer(0, id, 3);
    cs(0);
    return (id[0] << 16) | (id[1] << 8) | id[2];
}

/* Receive-only bursts: MTC = 0 lets the controller clock out dummy bytes itself (as Linux spi-sun6i does
 * for rx-only transfers), and the RX FIFO is drained byte by byte. Optionally folds each byte into a
 * running CRC32 (table in SRAM) so the data is not read back from uncached DRAM afterwards. */
static void rx_fast(u8 *d, u32 len, u32 *crc)
{
    const u32 *t = (const u32 *)CRC_TABLE_SRAM;
    while (len) {
        u32 n = len > 64 ? 64 : len;
        W32(SPI0 + SPI_MBC, n);
        W32(SPI0 + SPI_MTC, 0);
        W32(SPI0 + SPI_BCC, 0);
        W32(SPI0 + SPI_TCR, R32(SPI0 + SPI_TCR) | (1u << 31));
        while (R32(SPI0 + SPI_TCR) & (1u << 31))
            ;
        while ((R32(SPI0 + SPI_FSR) & 0xff) < n)
            ;
        /* Byte reads, as Linux spi-sun6i: a 32-bit RXD read hung on hardware (2026-10-06), consistent
         * with it popping a single byte, so the FIFO filled and the controller stalled the burst. */
        for (u32 i = 0; i < n; i++)
            d[i] = R8(SPI0 + SPI_RXD);
        if (crc) {
            u32 c = *crc;
            for (u32 k = 0; k < n; k++)
                c = t[(c ^ d[k]) & 0xff] ^ (c >> 8);
            *crc = c;
        }
        d += n;
        len -= n;
    }
}

/* READ (0x03), 24-bit address, 64 KiB per command; crc (pre-inverted, may be 0) accumulates if given. */
void spinor_read_fast(u32 addr, void *dst, u32 len, u32 *crc)
{
    u8 *d = dst;
    while (len) {
        u32 n = len > 0x10000 ? 0x10000 : len;
        u8 cmd[4] = { 0x03, addr >> 16, addr >> 8, addr };
        cs(1);
        xfer(cmd, 0, 4);
        rx_fast(d, n, crc);
        cs(0);
        wdog_feed();
        addr += n;
        d += n;
        len -= n;
    }
}

/* READ (0x03), 24-bit address: the 16 MiB part needs no 4-byte mode. */
void spinor_read(u32 addr, void *dst, u32 len)
{
    u8 *d = dst;
    while (len) {                   /* 64 KiB per command so the watchdog can be fed */
        u32 n = len > 0x10000 ? 0x10000 : len;
        u8 cmd[4] = { 0x03, addr >> 16, addr >> 8, addr };
        cs(1);
        xfer(cmd, 0, 4);
        xfer(0, d, n);
        cs(0);
        wdog_feed();
        addr += n;
        d += n;
        len -= n;
    }
}
