  .globl _start
  .option norvc
_start:
  lui x1, 0xFFFFF
  addi x1, x1, -1
  lui x2, 0x1
  addi x3, x2, 2047
  addi x4, x2, -2048
  add x5, x3, x4
  sub x6, x3, x4
  andi x7, x1, 0x0FF
  ori x8, x4, -256
  xori x9, x1, -1
  slti x10, x4, -1
  sltiu x11, x4, -1
  addi x12, x0, 1
  slli x12, x12, 31
  srli x13, x12, 31
  addi x14, x0, -1
  srai x14, x14, 31
  slt x15, x4, x3
  sltu x16, x4, x3
  auipc x17, 0
  addi x30,x0,1; li gp, 1; csrrw x0,0x3ff,x30
