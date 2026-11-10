# t48b: probe spike 0xB81 / 0xB84 / 0xB9F / 0xBA0 / 0xB20
  .globl _start
  .option norvc
_start:
  .word 0xB8102FF3          # csrrs x31, 0xB81, x0
  .word 0xB8402FF3          # csrrs x31, 0xB84, x0
  .word 0xBA002FF3          # csrrs x31, 0xBA0, x0
  .word 0xB2002FF3          # csrrs x31, 0xB20, x0
  halt:
  li gp, 1
  csrrw x0, 0x3ff, gp
  j .
