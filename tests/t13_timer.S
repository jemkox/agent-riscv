  .globl _start
  .option norvc
_start:
  li t0,0x800
  csrrw x0,mstatus,t0
  la t1,handler
  csrrw x0,mtvec,t1
  li t2,5
  csrrw x0,0x705,t2
  addi a0,x0,1
  addi a1,x0,2
  addi a2,x0,3
  addi a3,x0,4
  addi a4,x0,5
  addi a5,x0,6
handler:
  csrrw x0,mstatus,x0
  csrr a0,mcause
  li a1,0x1000
  sw a0,4(a1)
  csrr a2,mepc
  sw a2,8(a1)
  li a3,0xffffffff
  csrrw x0,0x705,a3
  li a4,1
  csrrw x0,0x3ff,a4
