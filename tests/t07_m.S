  .globl _start
  .option norvc
_start:
  addi x1, x0, 7
  addi x2, x0, 2
  sub x3, x0, x1
  mul x4, x1, x2
  mul x5, x3, x2
  div x6, x1, x2
  rem x7, x1, x2
  div x8, x3, x2
  rem x9, x3, x2
  lui x10, 0x80000
  div x11, x10, x3
  rem x12, x10, x3
  div x13, x10, x0
  rem x14, x10, x0
  divu x15, x10, x2
  remu x16, x10, x2
  divu x17, x10, x0
  remu x18, x10, x0
  mul x19, x10, x10
  mulh x20, x10, x10
  mulh x21, x10, x3
  mulhu x22, x10, x10
  mulhsu x23, x10, x10
  mul x24, x1, x0
  mulh x25, x3, x1
  lui x28, 0
  sw x1, 0(x28)
  lw x26, 0(x28)
  mul x27, x26, x2
  addi x30,x0,1; li gp, 1; csrrw x0,0x3ff,x30
