# u5a-loader (docs/boot-and-flash.md). Built with arm-none-eabi-gcc.
CROSS ?= arm-none-eabi-
CFLAGS = -mcpu=cortex-a7 -marm -mfloat-abi=soft -Os -ffreestanding -fno-builtin -nostdlib \
         -fno-pic -fno-stack-protector -Wall -Wextra -Werror
# Your own full 16 MiB flash dump, taken before the first install (blobs/README.md)
FACTORY ?= ../blobs/factory-flash.bin
OBJS = start.o main.o spi.o

all: u5a-loader-probe.img u5a-loader-return.img u5a-loader-boot.img

%.o: %.c loader.h
	$(CROSS)gcc $(CFLAGS) -c -o $@ $<
%.o: %.S
	$(CROSS)gcc $(CFLAGS) -c -o $@ $<
u5a-loader.elf: $(OBJS) link.ld
	$(CROSS)ld -T link.ld -o $@ $(OBJS) $$($(CROSS)gcc -print-libgcc-file-name)
u5a-loader.bin: u5a-loader.elf
	$(CROSS)objcopy -O binary $< $@
u5a-loader-probe.img: u5a-loader.bin mkimage.py
	python3 mkimage.py $(FACTORY) $< $@
	$(CROSS)objdump -d u5a-loader.elf > u5a-loader.disasm.txt
clean:
	rm -f *.o *.elf *.bin *.img *.disasm.txt
.PHONY: all clean

# Return-to-FEL probe: linked at 0x42000640 like the real loader, entered at 0x42000640 by xfel exec.
# The return probe only runs the fast read: `xfel exec` must come back within a few seconds or FEL ends up
# half-dead (two 4 MiB passes, about 8 s, did that twice on 2026-10-06).
main-ret.o: main.c loader.h
	$(CROSS)gcc $(CFLAGS) -DCRC_TABLE_SRAM=0x43f01000u -DPROBE_FAST_ONLY -c -o $@ $<
spi-ret.o: spi.c loader.h
	$(CROSS)gcc $(CFLAGS) -DCRC_TABLE_SRAM=0x43f01000u -c -o $@ $<
u5a-loader-return.elf: start_return.o main-ret.o spi-ret.o link.ld
	$(CROSS)ld -T link.ld -o $@ start_return.o main-ret.o spi-ret.o $$($(CROSS)gcc -print-libgcc-file-name)
u5a-loader-return.img: u5a-loader-return.elf
	$(CROSS)objcopy -O binary $< $@

# Production boot path (boot.c), padded to the factory u-boot item length 0x3c000 for the TOC1.
main-boot.o: main.c loader.h
	$(CROSS)gcc $(CFLAGS) -DMODE_BOOT -c -o $@ $<
u5a-loader-boot.elf: start.o main-boot.o boot.o spi.o mmu.o link.ld
	$(CROSS)ld -T link.ld -o $@ start.o main-boot.o boot.o spi.o mmu.o $$($(CROSS)gcc -print-libgcc-file-name)
u5a-loader-boot.bin: u5a-loader-boot.elf
	$(CROSS)objcopy -O binary $< $@
u5a-loader-boot.img: u5a-loader-boot.bin mkimage.py
	python3 mkimage.py $(FACTORY) $< $@ --pad 0x3c000
	$(CROSS)objdump -d u5a-loader-boot.elf > u5a-loader-boot.disasm.txt
