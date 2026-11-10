# probe menvcfg rw
 .globl _start
 .option norvc
_start:
 li x28,0x555
 .word 0x30AE1373
 .word 0x30A02FF3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
