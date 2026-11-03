# t20: reserved atomics and MMIO atomic traps must trap, not execute/leak.
# gp=1 only when every bad atomic traps (handler increments s0 and mrets past it).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t0, 0x800
  csrw mstatus, t0
  la t1, handler
  csrw mtvec, t1
  li s0, 0
  .word 0x0000302f          # amo.d (f3=011) reserved atomic size
  .word 0x2800202f          # funct5=00101 reserved atomic op
  .word 0x1010202f          # LR.W with rs2 field != 0
  li t2, 0x02000000
  .word 0x0003a02f          # amoadd.w to CLINT page
  li t2, 0x10000000
  .word 0x0003a02f          # amoadd.w to UART page
  li t2, 0x02000000
  .word 0x1003a02f          # lr.w from CLINT page
  li t3, 6
  bne s0, t3, fail
  li gp, 1
  li t4, 1
  csrrw x0, 0x3ff, t4
fail:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
