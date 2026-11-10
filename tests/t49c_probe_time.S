# t49c: 3 marks: 50k-loop then TIME; 50k-loop then TIME; 50k-loop then TIME.
  .globl _start
  .option norvc
_start:
  li t1, 50000
l1: addi t1,t1,-1
  bnez t1, l1
  .word 0xC01027F3
  li t1, 50000
l2: addi t1,t1,-1
  bnez t1, l2
  .word 0xC01027F3
  li t1, 50000
l3: addi t1,t1,-1
  bnez t1, l3
  .word 0xC01027F3
  li gp, 1
  csrrw x0, 0x3ff, gp
  j .
