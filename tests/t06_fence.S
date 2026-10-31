  .globl _start
  .option norvc
_start:
  addi x1, x0, 1
  fence
  ecall
