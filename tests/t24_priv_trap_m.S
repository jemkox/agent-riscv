# t24: trap from M-mode saves MPP=3; mret returns through mepc+4.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x1800
  csrw mstatus, t0
  ecall
  li t0, 1
  bne s0, t0, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 11
  bne t2, t3, fail
  csrr t2, mstatus
  li t3, 0x1800
  and t2, t2, t3
  li t3, 0x1800
  bne t2, t3, fail
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
