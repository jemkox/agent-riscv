  .globl _start
  .option norvc
_start:
  addi x9, x0, 1
  csrrwi x0, mie, 17
  csrrwi x0, mtvec, 5
  csrrwi x0, mepc, 9
  csrrwi x0, mcause, 3
  csrrs x1, mie, x0
  csrrs x2, mtvec, x0
  csrrs x3, mepc, x0
  csrrs x4, mcause, x0
  csrrw x0, 0x3ff, x9
