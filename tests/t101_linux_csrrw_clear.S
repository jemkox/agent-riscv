# t101_linux_csrrw_clear.S - Linux trap-stack switch clear check.
# Start in the "already switched" state: tp=mscratch=0x11111111.
# Execute the taken branch path and the final csrw mscratch,zero.
# a0 must read 0; pass halts with gp=1, fail halts with gp=3.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li tp, 0x11111111
  li sp, 0x22222222
  li t1, 0x11111111
  csrw mscratch, t1
  csrrw tp, mscratch, tp
  bnez tp, taken
  csrr tp, mscratch
taken:
  csrr s5, mscratch
  csrw mscratch, zero
  csrr a0, mscratch
  li gp, 1
  beq a0, zero, ok
  li gp, 3
  csrrw x0, 0x3ff, gp
ok:
  csrrw x0, 0x3ff, gp
end:
  j end
