# t39: IRQ gating corners (post 40c5649 review). Two pins:
#  A) at M with mideleg[MTI]=1 (S handler), MIE set, mtimecmp overdue: the
#     delegated MTI must NOT be taken at M (less-privileged handler).
#  B) at S (entered by mret MPP=S) with mideleg[MTI]=0, MIE hidden at S: the
#     pending MTI (handler M) must trap despite SIE/MIE being off (satp=0).
# If A is mis-gated (taken at M) or B is mis-gated (gated by SIE), the flow
# falls into fail (gp=3). Correct flow: two handler entries -> mret chain ->
# done, gp=1. mmucheck: a6==10 before lBmark, a6==10 before done.
  .globl _start
  .option norvc
_start:
  li gp,0
  la t1,handler
  csrw mtvec,t1
  li t4,0x80
  csrw 0x304,t4                       # mie.MTI
  csrs 0x303,t4                       # mideleg.MTI -> S handler (BEFORE pending exists)
  lui t2,0x2001
  sw x0,-2048(t2)                     # mtimecmp_lo=0
  sw x0,-2044(t2)                     # mtimecmp_hi=0 -> overdue
  li t0,8
  csrs mstatus,t0                     # MIE -> pending MTI armed now (delegated to S)
  li a6,0xA
lA:
  addi a0,x0,1
  addi a1,x0,2
  csrc 0x303,t4                       # clear mideleg bit7: MTI handled by M now
  j scode                            # buggy-A trap skipped this insn; correct: trapped here
lBmark:
  # mmucheck lBmark a
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
  sw t5,-2044(t6)                     # push mtimecmp far
  la t3,done
  csrw mepc,t3
  li t0,0x1818                        # MPP=M, MPIE, MIE
  csrw mstatus,t0
  mret
  # mmucheck done a
