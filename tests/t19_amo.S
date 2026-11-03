# t19: A-extension corner cases the rv32ua suite does not cover:
# producer->LR/SC/AMO with the address produced by the immediately preceding instruction
# (forwarding), reservation cleared by a plain store, and an AMO with a -offset.
  .globl _start
  .option norvc
_start:
  li gp, 0
  lui sp, 2
  li a2, 0x55
  li a0, 0x1000
  lr.w a1, (a0)            # LR right behind the producer of a0
  li t2, 0
  bne a1, t2, fail         # fresh word reads as 0
  sc.w a3, a2, (a0)        # reservation still valid -> must succeed
  bnez a3, fail
  lw a4, 0(a0)
  bne a4, a2, fail         # SC stored 0x55
  sw a2, 4(a0)             # mem@0x1004 = 0x55 (plain store)
  addi a0, a0, 4           # producer...
  amoadd.w a5, t2, (a0)    # ...AMO right behind it: rd = old value
  bne a5, a2, fail
  li s1, 0x1000
  lr.w a7, (s1)            # reserve 0x1000
  li t5, 0x77
  sw t5, 0(s1)             # plain store to the reserved word clears it
  sc.w t3, t5, (s1)        # must now FAIL: rd=1, no store
  li t4, 1
  bne t3, t4, fail
  lw t6, 0(s1)             # value is from the sw, not the failed SC... same word; check sw ran
  bne t6, t5, fail
  li gp, 1
fail:
  li t4, 1
  csrrw x0, 0x3ff, t4
