# probe w-then-read
 .globl _start
 .option norvc
_start:
 li x28,0x1234567f
 .word 0x7a4e12f3
 .word 0x7a402FF3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
