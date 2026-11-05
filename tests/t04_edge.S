  .globl _start
  .option norvc
_start:
  addi x0, x0, 5
  lui x0, 0xABCDE
  addi x1, x0, 0
  slli x1, x1, 0
  addi x2, x0, -1
  slli x3, x2, 31
  srli x4, x3, 31
  srai x5, x3, 31
  addi x6, x0, 31
  sll x7, x2, x6
  srl x8, x3, x6
  sra x9, x3, x6
  sub x10, x0, x2
  slt x11, x2, x0
  sltu x12, x2, x0
  jal x0, sk
  addi x13, x0, 1
sk:
  lw x0, 0(x0)
  addi x30,x0,1; li gp, 1; csrrw x0,0x3ff,x30
