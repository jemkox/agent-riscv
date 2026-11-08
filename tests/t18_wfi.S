# t18: WFI both paths (L1) + SELF-CHECKING branches.
# With mie.MTIE + mstatus.MIE and mtpcmp armed to 0, the pending IRQ kills the
# FIRST instruction after the mtpcmp store: that is the wfi itself (mepc = wfi
# pc, mcause = 0x8000_0007, mip reads 0x80 in the handler).  The handler pushes
# mtpcmp far away and mrets; the SAME wfi then re-executes with nothing pending
# and retires as a NOP (the mcycle pair ticks across it; mip now reads 0).
# Branch checks: mcause==0x80000007, mepc==w1, mip==0x80 (handler), mcycle
# strictly increasing, mip==0 after.  fail: -> gp=2 (ISS --pass gate wants gp==1).
# WFI encoded .word 0x10000073 (SYSTEM f3=0 csr 0x100; 0x00100073 is EBREAK).
_start:
  li t0,8                    # mstatus.MIE
  csrrw x0,mstatus,t0
  la t1,thdl
  csrrw x0,mtvec,t1
  li t5,0x80                 # mie.MTIE
  csrrw x0,0x304,t5
  lui a1,0x2                 # scratch 0x1800 (BEFORE arming so it is not killed)
  addi a1,a1,-2048
  la t0,w1                   # pc of the wfi the armed trap will kill (set before arming)
  lui t2,0x2001              # CLINT page base
  sw x0,-2044(t2)            # mtimecmp_hi = 0
  sw x0,-2048(t2)            # mtimecmp_lo = 0 -> overdue from the next commit
w1:
  .word 0x10000073           # wfi: MTI kills it at its own commit, mepc = w1
  j after                    # skip the handler (only falls in after the NOP path)
thdl:
  csrr t3,mcause
  sw t3,4(a1)                # expect 0x80000007
  li t4,0x80000007
  bne t3,t4,fail             # SELF-CHECK: mcause == 0x80000007 (timer IRQ)
  csrr t5,mepc
  sw t5,8(a1)                # expect the pc t0 was set to (w1)
  bne t5,t0,fail             # SELF-CHECK: mepc == the killed wfi pc
  csrr t6,0x344              # mip inside handler (still pending; mip = 0x344)
  sw t6,12(a1)
  li t4,0x80
  bne t6,t4,fail             # SELF-CHECK: mip == 0x80 in the handler
  lui t2,0x2001
  li t5,0xFFFFFFFF
  sw t5,-2048(t2)            # push mtimecmp far away (hi and lo)
  sw t5,-2044(t2)
  mret                       # back to w1; now not pending -> NOP retire
after:
  csrr t3,mcycle             # mcycle before the re-executed wfi
  sw t3,16(a1)
  .word 0x10000073           # wfi: not pending -> retires as NOP
  csrr t1,mcycle
  sw t1,20(a1)               # expect > value stored at 0x1810
  sltu t4,t3,t1
  beqz t4,fail               # SELF-CHECK: mcycle ticks across the wfi NOP
  csrr t2,0x344              # mip now clear (mtpcmp pushed)
  sw t2,24(a1)
  bne t2,x0,fail             # SELF-CHECK: mip == 0 after mtpcmp push
  li gp,1                  # gp is x3: ISS --pass gate demands gp==1 on XHALT
  csrrw x0,0x3ff,gp
fail:
  li t4,2                    # gp != 1 => ISS --pass gate FAILs this test
  csrrw x0,0x3ff,t4
