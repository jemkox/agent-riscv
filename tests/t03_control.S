  .globl _start
  .option norvc
_start:
  addi x1, x0, 5
  addi x2, x0, 5
  addi x4, x0, 0
  beq x1, x2, L1
  addi x4, x4, 1
L1:
  bne x1, x2, L2
  addi x4, x4, 1
L2:
  addi x5, x0, -1
  blt x5, x1, L3
  addi x4, x4, 8
L3:
  bge x5, x1, L4
  addi x4, x4, 16
L4:
  bltu x5, x1, L5
  addi x4, x4, 32
L5:
  bgeu x5, x1, L6
  addi x4, x4, 64
L6:
  jal x6, func
  addi x7, x0, 2
  j end
func:
  addi x8, x0, 42
  add x9, x8, x8
  jalr x0, 0(x6)
end:
  addi x30, x0, 10
  addi x20, x0, 0
lp:
  addi x20, x20, 1
  addi x30, x30, -1
  bne x30, x0, lp
  ebreak
