  .globl _start
  .option norvc
_start:
  addi t0,x0,1
  slli t0,t0,11
  csrrw x0,mstatus,t0
  la t1,handler
  csrrw x0,mtvec,t1
  li t2,0x1000
  sw x0,0(t2)
  li t3,0xa5
  ecall
handler:
  csrr t5,mcause
  sw t5,4(t2)
  csrr t6,mepc
  sw t6,8(t2)
  sw t3,12(t2)
  li t4,1
  csrrw x0,0x3ff,t4
