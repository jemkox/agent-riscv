# t103_csr_dest_nop.S - CSR destination forwarding test with a nop before use.
  .globl _start
  .option norvc
_start:
  li tp, 0x11111111
  li t1, 0x11111111
  csrw mscratch, t1
  csrrw tp, mscratch, tp
  nop
  addi tp, tp, 0
  csrrw x0, 0x3ff, tp
end:
  j end
