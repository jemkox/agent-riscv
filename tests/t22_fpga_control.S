  .globl _start
  .option norvc
_start:
  addi x1, x0, 3
  addi x2, x0, 5
  lui x10, 1
  sw x1, 0(x10)
  lw x11, 0(x10)
  beq x11, x1, after_load
  addi x12, x0, 111
  addi x13, x0, 112
after_load:
  jal x14, after_jal
  addi x15, x0, 113
  addi x16, x0, 114
after_jal:
  addi x17, x0, 115
  addi x18, x0, 0
  beq x18, x0, taken_cond
  addi x19, x0, 116
taken_cond:
  sw x2, 4(x10)
  lw x20, 4(x10)
  beq x20, x2, after_load_use
  addi x21, x0, 117
after_load_use:
  addi x22, x0, 118
  beq x22, x0, skipped
  addi x23, x0, 119
skipped:
  addi x9, x0, 1
  li gp, 1; csrrw x0, 0x3ff, x9
