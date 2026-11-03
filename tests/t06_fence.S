  .globl _start
  .option norvc
_start:
  addi x1, x0, 1
  fence
  addi x30,x0,1; csrrw x0,0x3ff,x30
