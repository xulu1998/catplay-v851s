#ifndef U5A_LOADER_H
#define U5A_LOADER_H
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef unsigned long long u64;
#define R32(a) (*(volatile u32 *)(a))
#define W32(a, v) (*(volatile u32 *)(a) = (v))
#define R8(a) (*(volatile u8 *)(a))
#define W8(a, v) (*(volatile u8 *)(a) = (v))

void spi_init(void);
u32 spinor_jedec_id(void);
void spinor_read(u32 addr, void *dst, u32 len);
void wdog_feed(void);
void spinor_read_fast(u32 addr, void *dst, u32 len, u32 *crc);
void crc32_table_init(void);
void mmu_on(void);
void clean_caches(void);
#ifndef CRC_TABLE_SRAM                 /* 1 KiB; SRAM A1 on the boot path (free after Boot0) */
#define CRC_TABLE_SRAM 0x0003b000u   /* the return-to-FEL probe builds with a DRAM address instead */
#endif
void wdog_arm(void);
u64 ticks(void);
u32 crc32(const u8 *p, u32 len);
void prepare_hardware(void);
#endif
