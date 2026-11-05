# t25: mret with saved MPP=0 enters U; ecall from U saves cause 8 and saved MPP=0.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  csrw mstatus, x0
  la t1, uecall
  csrw mepc, t1
  mret
uecall:
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
  li t3, 8
  bne t2, t3, fail
  la t3, uecall
  csrr t2, mepc
  bne t2, t3, fail
  csrr t2, mstatus
  li t3, 0x1800
  and t2, t2, t3
  bne t2, x0, fail
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
