# probe
 .globl _start
 .option norvc
_start:
 li t1,50000
l1: addi t1,t1,-1
 bnez t1,l1
 .word 0xC01027F3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
