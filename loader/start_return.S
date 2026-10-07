/* Probe entry that returns to the BootROM FEL loop (like xfel's own payloads): no cache/MMU changes,
 * runs on the FEL stack. Used to read the report with `xfel read` without starting a kernel. */
.syntax unified
.cpu cortex-a7
.arm
.section .text.entry, "ax"
.global _start
_start:
    push {r4-r12, lr}
    mrs r0, cpsr
    mrc p15, 0, r1, c1, c0, 0
    ldr r2, =__bss_start
    ldr r3, =__bss_end
    mov r4, #0
1:  cmp r2, r3
    strlo r4, [r2], #4
    blo 1b
    bl probe_return_main
    dsb sy
    pop {r4-r12, pc}
