    .globl _start
    .text
_start:
    auipc t0, 0
    li t1, 0x14
    add t0, t0, t1
    csrw 0x341, t0        # mepc = instruction after the mret below
    mret                  # ISS --high makes this an explicit high-PC mret
    csrr s0, 0x300        # after mret: Linux --linux-mpp clears MPP; standard keeps it
    li t1, 0x1800
    and s0, s0, t1
    beq s0, zero, pass
fail:
    li gp, 3
    csrrw x0, 0x3ff, gp
    csrw 0x3ff, 1
pass:
    li gp, 1
    csrrw x0, 0x3ff, gp
    csrw 0x3ff, 1
