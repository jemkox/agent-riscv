# t103_csr_dest_nop.S - CSR destination forwarding test with a nop before use.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li tp, 0x11111111
  li t1, 0x22222222
  csrw mscratch, t1
  csrrw tp, mscratch, tp
  nop
  bne tp, t1, bad
  li gp, 1
  csrrw x0, 0x3ff, gp
bad:
  li gp, 3
  csrrw x0, 0x3ff, gp
end:
  j end
