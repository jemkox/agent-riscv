  .globl _start
  .option norvc
_start:
  lui x10, 1
  addi x1, x0, 0x55
  addi x2, x0, -86
  addi x3, x0, 0x33
  addi x4, x0, -52
  sw x0, 0(x10)
  sb x1, 0(x10)
  sb x2, 1(x10)
  sb x3, 2(x10)
  sb x4, 3(x10)
  lbu x6, 0(x10)
  lbu x7, 1(x10)
  lbu x8, 2(x10)
  lbu x9, 3(x10)
  lb x11, 0(x10)
  lb x12, 1(x10)
  lb x13, 2(x10)
  lb x14, 3(x10)
  sh x1, 0(x10)
  sh x2, 2(x10)
  lh x15, 0(x10)
  lh x16, 2(x10)
  lhu x17, 0(x10)
  lhu x18, 2(x10)
  sb x1, 0(x10)
  sb x2, 1(x10)
  sb x3, 2(x10)
  sb x4, 3(x10)
  lbu x19, 0(x10)
  lbu x20, 1(x10)
  lbu x21, 2(x10)
  lbu x22, 3(x10)
  lh x23, 0(x10)
  lh x24, 2(x10)
  lhu x25, 0(x10)
  lhu x26, 2(x10)
  lb x27, 0(x10)
  lb x28, 1(x10)
  lb x29, 2(x10)
  lb x30, 3(x10)
  sw x3, 0(x10)
  sb x4, 1(x10)
  sb x1, 2(x10)
  sb x2, 3(x10)
  lbu x5, 3(x10)
  lb x6, 2(x10)
  lh x7, 0(x10)
  lhu x8, 0(x10)
  addi x9, x0, 1
  csrrw x0, 0x3ff, x9
