  .globl _start
  .option norvc
_start:
  jal x1, A
  addi x2, x1, 0
  jal x3, B
  jal x4, C
  jal x0, done
A:
  addi x5, x0, 10
  jalr x0, 0(x1)
B:
  addi x6, x0, 20
  jalr x0, 0(x3)
C:
  addi x7, x0, 30
  jalr x0, 0(x4)
done:
  jal x0, skip
  addi x8, x0, 111
skip:
  addi x8, x0, 222
  beq x8, x8, d1
  addi x9, x0, 1
d1:
  addi x30,x0,1; csrrw x0,0x3ff,x30
