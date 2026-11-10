# probe menvcfg mask
 .globl _start
 .option norvc
_start:
 li x28,-1
 .word 0x30AE1373
 .word 0x30A02FF3
 li x28,0x80000008
 .word 0x30AE1373
 .word 0x30A02FF3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
