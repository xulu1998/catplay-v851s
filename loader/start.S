/* u5a-loader entry. Boot0 (or FEL in E29) enters at 0x42000000, which is the copied U-Boot head;
 * its first word branches here (0x42000640). Entry cleanup is the launch.bin sequence used E01-E28. */
.syntax unified
.cpu cortex-a7
.arm
.section .text.entry, "ax"
.global _start
_start:
    cpsid if
    mrs r4, cpsr                 /* entry state for the report */
    mrc p15, 0, r5, c1, c0, 0    /* SCTLR at entry */
    ldr sp, =__stack_top
    bl clean_caches
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #1               /* MMU off */
    bic r0, r0, #4               /* D-cache off */
    bic r0, r0, #0x1000          /* I-cache off for the invalidate */
    mcr p15, 0, r0, c1, c0, 0
    dsb sy
    isb
    mov r0, #0
    mcr p15, 0, r0, c8, c7, 0    /* TLBs */
    mcr p15, 0, r0, c7, c5, 0    /* I-cache */
    mcr p15, 0, r0, c7, c5, 6    /* branch predictor */
    dsb sy
    isb
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #0x1000          /* I-cache on (safe with MMU off): the CRC loop runs from DRAM */
    mcr p15, 0, r0, c1, c0, 0
    isb
    ldr r0, =24000000
    mrc p15, 0, r1, c14, c0, 0   /* CNTFRQ: only write it if needed; the write is Secure-PL1 only and */
    cmp r0, r1                   /* undefined otherwise. Boot0 already uses the 24 MHz counter. */
    mcrne p15, 0, r0, c14, c0, 0
    ldr r0, =__bss_start
    ldr r1, =__bss_end
    mov r2, #0
1:  cmp r0, r1
    strlo r2, [r0], #4
    blo 1b
    mov r0, r4
    mov r1, r5
    bl loader_main               /* returns the kernel entry, or never returns */
    mov r6, r0
    bl clean_caches              /* write back everything the loader put in DRAM through the D-cache */
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #0x1000          /* leave with MMU and all caches off, as launch.bin */
    bic r0, r0, #0x4
    bic r0, r0, #0x1
    mcr p15, 0, r0, c1, c0, 0
    isb
    bl clean_caches              /* nothing new can be cached now; invalidates the remaining lines */
    mov r0, #0
    mcr p15, 0, r0, c8, c7, 0    /* TLBs */
    mcr p15, 0, r0, c7, c5, 0    /* I-cache */
    mcr p15, 0, r0, c7, c5, 6    /* branch predictor */
    dsb sy
    isb
    mov r12, r6
    mov r0, #0
    mvn r1, #0
    ldr r2, =0x43000000
    bx r12

.global clean_caches
clean_caches:                    /* clean+invalidate all data cache levels by set/way (launch.bin) */
    push {r4-r11, lr}
    dsb sy
    mrc p15, 1, r0, c0, c0, 1
    ubfx r3, r0, #24, #3
    lsl r3, r3, #1
    mov r10, #0
1:  cmp r10, r3
    bge 5f
    add r2, r10, r10, lsr #1
    lsr r1, r0, r2
    and r1, r1, #7
    cmp r1, #2
    blt 4f
    mcr p15, 2, r10, c0, c0, 0
    isb
    mrc p15, 1, r1, c0, c0, 0
    and r2, r1, #7
    add r2, r2, #4
    ubfx r4, r1, #3, #10
    clz r5, r4
    ubfx r7, r1, #13, #15
2:  mov r9, r4
3:  orr r11, r10, r9, lsl r5
    orr r11, r11, r7, lsl r2
    mcr p15, 0, r11, c7, c14, 2
    subs r9, r9, #1
    bge 3b
    subs r7, r7, #1
    bge 2b
4:  add r10, r10, #2
    b 1b
5:  mov r0, #0
    mcr p15, 2, r0, c0, c0, 0
    dsb sy
    isb
    pop {r4-r11, pc}
