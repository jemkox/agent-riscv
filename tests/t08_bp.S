  .globl _start
  .option norvc
_start:
  addi x2, x0, 5
loop1:
  addi x1, x1, 3
  addi x2, x2, -1
  bne x2, x0, loop1
  bne x2, x0, skip
  addi x3, x0, 77
skip:
  jal x1, helper
  addi x4, x0, 55
  jal x1, helper
  addi x5, x0, 66
  jal x0, done
done:
  ebreak
helper:
  addi x10, x10, 9
  blt x0, x10, ret
  addi x10, x10, 7
ret:
  jalr x0, 0(x1)
