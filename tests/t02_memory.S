  .globl _start
  .option norvc
_start:
  lui x28, 0x1
  lw x1, 0(x28)
  lw x2, 4(x28)
  lb x3, 0(x28)
  lbu x4, 0(x28)
  lh x5, 2(x28)
  lhu x6, 2(x28)
  lb x7, 1(x28)
  lw x8, -4(x28)
  addi x9, x0, 97
  sb x9, 3(x28)
  lw x10, 0(x28)
  addi x11, x0, 123
  sh x11, 6(x28)
  lw x12, 4(x28)
  sw x11, 8(x28)
  lw x13, 8(x28)
  lb x14, 11(x28)
  addi x30,x0,1; csrrw x0,0x3ff,x30
.data
.word 0xDEADBEEF
.word 0x12345678
.word 0xFFFFFFFF
.word 0x000000FF
.word 0x7FFFFFFF
.word 0x80000000
