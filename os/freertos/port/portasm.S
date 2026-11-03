/* FreeRTOS port for the rv32cpu pipeline: trap entry and context save/restore.
 * Frame (32 words, on the task's stack): word 0 = mepc, word i = register xi; sp, gp, tp not saved. */
    .option norvc
    .equ FRAME, 128
    .equ MSTATUS_TRAPS_ON, 0x1800

    .section .bss
    .align 4
xISRStack:
    .space 1024
xISRStackTop:

    .section .text
    .align 4
    .global vPortTrapEntry
vPortTrapEntry:
    /* mtvec: the hardware never takes the timer interrupt at this address, so disabling here is safe. */
    csrw mstatus, zero
    addi sp, sp, -FRAME
    sw x1, 4(sp)
    sw x5, 20(sp)
    sw x6, 24(sp)
    sw x7, 28(sp)
    sw x8, 32(sp)
    sw x9, 36(sp)
    sw x10, 40(sp)
    sw x11, 44(sp)
    sw x12, 48(sp)
    sw x13, 52(sp)
    sw x14, 56(sp)
    sw x15, 60(sp)
    sw x16, 64(sp)
    sw x17, 68(sp)
    sw x18, 72(sp)
    sw x19, 76(sp)
    sw x20, 80(sp)
    sw x21, 84(sp)
    sw x22, 88(sp)
    sw x23, 92(sp)
    sw x24, 96(sp)
    sw x25, 100(sp)
    sw x26, 104(sp)
    sw x27, 108(sp)
    sw x28, 112(sp)
    sw x29, 116(sp)
    sw x30, 120(sp)
    sw x31, 124(sp)
    csrr t0, mepc
    sw t0, 0(sp)
    lw t0, pxCurrentTCB
    sw sp, 0(t0)                 /* pxTopOfStack is the TCB's first member */
    la sp, xISRStackTop
    csrr a0, mcause
    csrr a1, mepc
    call vPortTrapHandler
    /* fall through: run whichever task is current now */

    .global vPortStartFirstTask
vPortStartFirstTask:
    lw t0, pxCurrentTCB
    lw sp, 0(t0)
    lw t0, 0(sp)
    csrw mepc, t0
    lw x1, 4(sp)
    lw x6, 24(sp)
    lw x7, 28(sp)
    lw x8, 32(sp)
    lw x9, 36(sp)
    lw x10, 40(sp)
    lw x11, 44(sp)
    lw x12, 48(sp)
    lw x13, 52(sp)
    lw x14, 56(sp)
    lw x15, 60(sp)
    lw x16, 64(sp)
    lw x17, 68(sp)
    lw x18, 72(sp)
    lw x19, 76(sp)
    lw x20, 80(sp)
    lw x21, 84(sp)
    lw x22, 88(sp)
    lw x23, 92(sp)
    lw x24, 96(sp)
    lw x25, 100(sp)
    lw x26, 104(sp)
    lw x27, 108(sp)
    lw x28, 112(sp)
    lw x29, 116(sp)
    lw x30, 120(sp)
    lw x31, 124(sp)
    /* Interrupts back on for the last three instructions; vPortTrapHandler left the next tick at
     * least TICK_MARGIN cycles away, and a pending yield was consumed, so nothing fires here. */
    li t0, MSTATUS_TRAPS_ON
    csrw mstatus, t0
    lw x5, 20(sp)
    addi sp, sp, FRAME
    mret
