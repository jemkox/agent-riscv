# probe
 .globl _start
 .option norvc
_start:
 li x28,0x1234567f
 .word 0x7a2e12f3
 .word 0x7a002ff3
 .word 0x7a102ff3
 .word 0x7a402ff3
 li x28,0x1234567f
 .word 0x7a3e12f3
 .word 0x7a002ff3
 .word 0x7a202ff3
 .word 0x7a402ff3
 li gp,1
 csrrw x0,0x3ff,gp
 j .
