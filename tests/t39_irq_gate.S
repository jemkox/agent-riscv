# t39: IRQ gating corners, spike-pinned mideleg/medeleg write masks (0x222/0xB109)
# (pinned spike 1.1.1-dev: `csrw mideleg,0x3ff` then read back -> 0x222; the
# MTI bit7 is NOT delegable on spike, so a "delegated MTI at M" scenario cannot
# exist there - the old pin A was rewritten to pin the mask itself).
# Pins:
#  A) mideleg write mask: csrw 0x303,0x3ff -> csrr a6,0x303 must read 0x222
#     (mmucheck maskmk 222).
#  B) at M with MIE armed and mtimecmp overdue: the pending MTI fires on the
#     FIRST retire after arming (handler entry 1); a6==0xA retired before lBmark.
#  C) at S (entered by mret MPP=S) with mideleg[MTI]=0 and SIE/MIE hidden/off:
#     the re-armed pending MTI MUST trap at `li a6,0xC` despite SIE/MIE being
#     off (handler is M); the buggy flow falls through to j fail. Entry 2 ->
#     step2 mepc=done + mret(MPP=M) -> done, gp=1.
# mmucheck: a6==0x222 before maskmk, a6==0xA before lBmark, a6==0xA before done.
  .globl _start
  .option norvc
_start:
  li gp,0
  la t1,handler
  csrw mtvec,t1
  li t4,0x3ff
  csrw 0x303,t4                       # mideleg attempt -> masked to 0x222 by spike
  csrr a6,0x303                       # a6 = 0x222 (spike writable mask pinned)
maskmk:
  # mmucheck maskmk 222
  lui t2,0x2001
  sw x0,-2048(t2)                     # mtimecmp_lo=0
  sw x0,-2044(t2)                     # mtimecmp_hi=0 -> overdue once mie armed
  li t0,0x80
  csrw 0x304,t0                       # mie.MTI
  li a6,0xA
  li t0,8
  csrs mstatus,t0                     # MIE -> pending MTI armed now (handler M)
lBmark:
  # mmucheck lBmark a
  addi a0,x0,1                        # trap here (mepc=this insn)
  addi a1,x0,2
  j scode                             # not reached
scode:
  lui t6,0x2001
  sw x0,-2048(t6)                     # re-arm overdue (store at S, satp=0)
  sw x0,-2044(t6)
  li a6,0xC                           # correct: traps here (mepc=this insn); buggy B: retires
  j fail                              # buggy B reaches; correct skipped (step2 mepc=done)
done:
  li gp,1
  li t4,1
  csrrw x0,0x3ff,t4                   # XHALT
fail:
  li gp,3
  li t4,1
  csrrw x0,0x3ff,t4
handler:
  csrr t0,mcause
  li t1,0x80000007
  bne t0,t1,fail
  addi s5,s5,1
  li a4,1
  beq s5,a4,step1
  li a4,2
  beq s5,a4,step2
  j fail                              # a third trap is wrong
step1:
  lui t6,0x2001
  li t5,0xffffffff
  sw t5,-2048(t6)
  sw t5,-2044(t6)                     # push mtimecmp far
  la t3,scode
  csrw mepc,t3
  csrr t0,mstatus
  li t1,0xFFFFE7FF                    # ~0x1800: clear MPP
  and t0,t0,t1
  li t2,0x800                         # MPP=S
  or t0,t0,t2
  csrw mstatus,t0
  mret
step2:
  lui t6,0x2001
  li t5,0xffffffff
  sw t5,-2048(t6)
  sw t5,-2044(t6)                     # push far
  la t3,done
  csrw mepc,t3
  li t0,0x1818                        # MPP=M, MPIE, MIE
  csrw mstatus,t0
  mret
  # mmucheck done a
