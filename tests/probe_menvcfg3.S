# probe menvcfg bits
 .globl _start
 .option norvc
_start:
 li x28,0x80000001
 .word 0x30AE1373
 .word 0x30A02FF3
 li x28,0x8
 .word 0x30AE1373
 .word 0x30A02FF3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
