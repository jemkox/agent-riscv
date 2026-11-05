# t102_csr_dest_fwd.S - CSR destination forwarding test.
# The csrrw writes old mscratch into tp. tp is then used by addi and branch.
  .globl _start
  .option norvc
_start:
  li tp, 0x11111111
  li t1, 0x11111111
  csrw mscratch, t1
  csrrw tp, mscratch, tp
  addi tp, tp, 0
  csrrw x0, 0x3ff, tp
end:
  j end
