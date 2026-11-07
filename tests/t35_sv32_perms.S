# t35: SUM/MXR and U pages (M and S). e5: U-page (R|W|U+A|D): S load w/o SUM ->
# PF13 (handler sets SUM, mepc+4 retry ok). e6: W-only page (R=0!): S load w/o
# MXR -> PF13 (handler sets MXR retry ok). e4: X|R|U page: jump from S -> IT
# PF12 (handler redirects to after-it label). s0 must be 3 and both loads return
# the same value at PA0xA000.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x8000
  li t1, 0x2401
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB           # e0 code identity R|X
  sw t1, 0(t0)
  li t1, 0x40B         # e1 code identity R|X
  sw t1, 4(t0)
  li t1, 0x24C7        # e9 L0 self page R|W
  sw t1, 36(t0)
  li t1, 0x2AD7        # e5: (0xA<<10)|R|W|U|A|D|V
  sw t1, 20(t0)
  li t1, 0x28C5        # e6: (0xA<<10)|W|A|D|V (R=0)
  sw t1, 24(t0)
  li t1, 0x285B        # e4: (0xA<<10)|X|R|U|A|V? U|X|R=0x18|0x8|0x2? U=0x10 X=8 R=2 =0x1A |A=0x40|V -> 0x5B? no D: 0x1A|0x40|1=0x5B
  sw t1, 16(t0)
  li t0, 0xA000
  li t1, 0x6161
  sw t1, 0(t0)
  li t0, 0x80000008
  csrw satp, t0
  # go to S-mode via mret (MPP=S)
  la t2, sblock
  csrw mepc, t2
  li t0, 0x1800
  csrc mstatus, t0     # clear MPP
  li t0, 0x800         # MPP=S
  csrs mstatus, t0
  mret
sblock:
  li t3, 0x5000        # U page: S load w/o SUM -> PF
  lw t2, 0(t3)
  li t4, 0x6161
  bne t2, t4, fail
  li t3, 0x6000        # W-only page: S load w/o MXR -> PF
  lw t2, 0(t3)
  li t4, 0x6161
  bne t2, t4, fail
  li t5, 0x4000        # X|R|U page: S fetch -> IT PF (supervisor may not exec U)
  jalr x0, 0(t5)
afterit:
  li t4, 3
  bne s0, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
  j done
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 12
  beq t2, t3, ithandler
  li t3, 13
  beq t2, t3, dthandler
  j fail
ithandler:
  csrr t2, mtval
  li t3, 0x4000
  bne t2, t3, fail
  addi s0, s0, 1
  la t2, afterit
  csrw mepc, t2
  j mret_only
dthandler:
  csrr t2, mtval
  addi s0, s0, 1
  li t3, 0x5000
  beq t2, t3, dosum
  li t3, 0x6000
  beq t2, t3, domxr
  j fail
dosum:
  li t0, 0x40000       # SUM
  csrs mstatus, t0
  j dtskip
domxr:
  li t0, 0x80000       # MXR
  csrs mstatus, t0
dtskip:
mret_only:
  mret
