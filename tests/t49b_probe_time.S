# t49b: run ~300K insns then read TIME/TIMEH at known retire counts (3 marks).
  .globl _start
  .option norvc
_start:
  li s0, 0
mark1:
  li t1, 100000
l1: addi t1,t1,-1
  bnez t1, l1
  .word 0xC01027F3          # csrrs a5, time
  .word 0xC8102FF3          # csrrs x31, timeh
  addi s0,s0,1
mark2:
  li t1, 100000
l2: addi t1,t1,-1
  bnez t1, l2
  .word 0xC01027F3          # csrrs a5, time
  .word 0xC8102FF3
  addi s0,s0,1
mark3:
  li t1, 100000
l3: addi t1,t1,-1
  bnez t1, l3
  .word 0xC01027F3
  .word 0xC8102FF3
  addi s0,s0,1
  li gp, 1
  csrrw x0, 0x3ff, gp
  j .
