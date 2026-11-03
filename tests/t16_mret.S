# t16: real mret (0x30200073). Found by the FreeRTOS port: the decoder matched 0x300, the ISS had no
# mret, and env/mi/riscv_test.h replaces mret with csrr mepc + jalr, so no test ran a real mret.
# Self-checking: gp=1 only if both mrets return where mepc points (make test runs the ISS with --pass).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t0, 0x1800
  csrw mstatus, t0          # traps on
  la t1, handler
  csrw mtvec, t1
  li s0, 0
  ecall                     # handler bumps mepc past the ecall and returns with mret
  addi s1, x0, 7
  li t0, 1
  bne s0, t0, fail          # handler ran exactly once
  la t1, target
  csrw mepc, t1
  mret                      # mret as a plain jump to mepc
  j fail
target:
  li t0, 7
  bne s1, t0, fail
  li gp, 1
fail:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 11
  bne t2, t3, fail          # machine ecall cause (M-mode ECALL = 0xb)
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
