# probe menvcfgh rw
 .globl _start
 .option norvc
_start:
 li x28,-1
 .word 0x31AE1373
 .word 0x31A02FF3
 .word 0x30A02FF3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
