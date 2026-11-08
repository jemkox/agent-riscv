.globl _start
  .option norvc
# Directed store-DATA forwarding cases.
# Symptom seen in the Linux boot: `addi sp,sp,-48` (result forwarded to the store's
# rs1) immediately followed by `sw ra,44(sp)` stored the *sp* result instead of
# ra. Cover back-to-back EX->store data forwarding, plus the store redone after
# a D-cache miss / load-use stall / CSR, across CACHE_LAT builds.
_start:
  lui x28, 0x1              # x28 = 0x1000 (data base = .data page)
  addi x30, x0, 0           # x30 = error accumulator (0 = all good)

  # --- case A: back-to-back addi (rd==sp==store rs1) then store with rs2 != rs1
  li x1, 0xA5A5A5A5         # "ra"
  li x2, 0x1200             # sp
  addi x2, x2, -48
  sw x1, 44(x2)             # [0x11C8+44? base 0x11B0] must hold 0xA5A5A5A5
  lw x3, 44(x2)
  li x4, 0xA5A5A5A5
  xor x5, x3, x4
  or x30, x30, x5

  # same but store imm 0 and store imm 48 (edge lanes)
  li x1, 0x11223344
  li x2, 0x1240
  addi x2, x2, -48
  sw x1, 0(x2)
  sw x1, 48(x2)
  lw x3, 0(x2)
  xor x5, x3, x1
  or x30, x30, x5
  lw x3, 48(x2)
  xor x5, x3, x1
  or x30, x30, x5

  # --- case B: cold store (D-cache miss on store) right after dependent addi
  li x2, 0x1400
  addi x2, x2, -48
  sw x1, 44(x2)             # cold line: first touch of this store's line
  lw x3, 44(x2)
  xor x5, x3, x1
  or x30, x30, x5

  # --- case C: load-use stall feeding the *next* store (rs2 = loaded value)
  lui x28, 0x1              # data base (same page as .data below)
  lw x10, 12(x28)           # x10 = 0x000000FF (word3)
  li x2, 0x1300
  sw x10, 44(x2)
  lw x3, 44(x2)
  li x4, 0x000000FF
  xor x5, x3, x4
  or x30, x30, x5

  # load-use stall where the *store address* base comes from a load too
  lw x6, 20(x28)            # x6 = 0x80000000 (word5)
  srli x6, x6, 31
  slli x6, x6, 5            # x6 = 32
  add x7, x28, x6           # x7 = 0x1020
  addi x7, x7, -48
  sw x10, 44(x7)            # [0x1020-4+44]
  lw x3, 44(x7)
  li x4, 0x000000FF
  xor x5, x3, x4
  or x30, x30, x5

  # --- case D: store immediately after a CSR read/write (rd=x0) then rs2 fwd chain
  csrrs x11, mepc, x0
  li x1, 0xDECF00DD
  sw x1, 44(x7)
  lw x3, 44(x7)
  xor x5, x3, x1
  or x30, x30, x5

  # --- case E: two-deep chain: addi sp; alu touching sp; store ra
  li x1, 0x5A5A1234
  li x2, 0x1480
  addi x2, x2, -48
  addi x9, x2, 44           # x9 = store addr (derived)
  sw x1, 0(x9)
  lw x3, 0(x9)
  xor x5, x3, x1
  or x30, x30, x5

  # --- case F: store half/byte right after sp-arith (lane check)
  li x1, 0xBEEFCAFE
  li x2, 0x14C0
  addi x2, x2, -48
  sh x1, 44(x2)
  lh x3, 44(x2)             # sign-extended half
  li x4, 0xFFFFCAFE
  xor x5, x3, x4
  or x30, x30, x5
  sb x1, 46(x2)
  lb x3, 46(x2)
  li x4, 0xFFFFFFFE          # low byte of 0xBEEFCAFE, sign-extended
  xor x5, x3, x4
  or x30, x30, x5

  # x30 holds the accumulated per-case diffs; zero means every load-back matched.
  slti x30, x30, 1          # x30 = 1 iff x30 == 0 (all good)
  beq x30, x0, _end_fail
  li gp, 1
  csrrw x0, 0x3ff, gp       # pass marker (same shape as t14: writes a 1)
_end_fail:
  csrrw x0, 0x3ff, x0       # fail: writes a 0

.data
.word 0xDEADBEEF
.word 0x12345678
.word 0xFFFFFFFF
.word 0x000000FF
.word 0x7FFFFFFF
.word 0x80000000
.word 0x0
.word 0x0
