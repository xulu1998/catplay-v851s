OUTPUT_ARCH(arm)
ENTRY(_start)
SECTIONS {
    /* Boot0 loads the 'u-boot' TOC1 item to 0x42000000 and writes its parameters into the first
     * 0x600 bytes; mkimage.py puts a copy of the factory U-Boot head there. Code starts at 0x640. */
    . = 0x42000640;
    .text : { *(.text.entry) *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    . = ALIGN(4);
    __bss_start = .;
    .bss : { *(.bss*) *(COMMON) }
    . = ALIGN(4);
    __bss_end = .;
    . = ALIGN(16);
    . += 0x4000;
    __stack_top = .;
    /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment*) *(.note*) }
    ASSERT(__stack_top < 0x42040000, "loader exceeds the 0x3c000 u-boot slot")
}
