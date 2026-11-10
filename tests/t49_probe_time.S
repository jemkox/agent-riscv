# t49_probe_time: read TIME (0xC01) / TIMEH (0xC81) at several points, then
# spin N nops and read again -> compute spike's mtime advance per retired insn.
  .globl _start
  .option norvc
_start:
  .word 0xC01027F3          # csrrs a5, time, x0   -> x15
  .word 0xC8102FF3          # csrrs x31, timeh, x0
  li t1, 300
loop:
  addi t1, t1, -1
  bnez t1, loop
  .word 0xC01027F3          # csrrs a5, time, x0
  .word 0xC8102FF3          # csrrs x31, timeh, x0
  li gp, 1
  halt:
  csrrw x0, 0x3ff, gp
  j .
