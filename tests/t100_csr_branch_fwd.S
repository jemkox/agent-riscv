# t100_csr_branch_fwd.S — CSR-write -> branch operand forwarding.
# After csrrw tp,mscratch,tp with mscratch=0, tp becomes 0 and the branch
# must not be taken. If the branch forwards the old tp it takes the bad path.
  .globl _start
  .option norvc
_start:
  li tp, 0x11111111
  csrw mscratch, zero
  li t0, 0x33333333
  csrrw tp, mscratch, tp
  bnez tp, bad
  li t1, 1
  csrrw x0, 0x3ff, t1
bad:
  li t1, 2
  csrrw x0, 0x3ff, t1
