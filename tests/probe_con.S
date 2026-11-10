# probe console
 .globl _start
 .option norvc
_start:
 li x28,0x1e000000
 sb 0x41,0(x28)
 li x28,0x10000000
 sb 0x42,0(x28)
 li x28,0x1f000000
 sb 0x43,0(x28)
 li gp,1
 csrrw x0,0x3ff,gp
 j .
