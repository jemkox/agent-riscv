  .globl _start
  .option norvc
_start:
  li t0,0x1000
  sw x0,0(t0)
  li t1,7
  csrrw x0,mcycle,t1
  csrrw x0,mcycle,x0
  csrrw x0,minstret,x0
  csrrw x0,mstatus,x0
  csrrw x0,mtvec,x0
  li t2,5
  csrrw x0,mscratch,t2
  csrr t3,mscratch
  sw t3,4(t0)
  addi x30,x0,1; li gp, 1; csrrw x0,0x3ff,x30
