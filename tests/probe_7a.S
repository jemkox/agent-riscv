# probe
 .globl _start
 .option norvc
_start:
 .word 0x7a702FF3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
