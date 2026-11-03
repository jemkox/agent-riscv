# t13: CLINT MMIO timer interrupt (L1).  Set mstatus.MIE, mie.MTI, zero
# mtimecmp at 0x0200_0800/0x0200_0804 -> timer overdue -> IRQ traps at the
# next insn boundary (mcause=0x80000007, mepc=addi a0).  Handler stores mcause
# and mepc at 0x1000, pushes mtimecmp far, halts via XHALT.  Gate: ISS/RTL log
# equality (cmp.py) makes both sides agree on the whole trap sequence.
  .globl _start
  .option norvc
_start:
  li t0,0x8                  # mstatus MIE (MPP forced by hardware)
  csrrw x0,mstatus,t0
  la t1,handler
  csrrw x0,mtvec,t1
  li t4,0x80                 # MTI in mie
  csrrw x0,0x304,t4
  lui t2,0x2001              # 0x02001000 (base for CLINT page, +/-2K offsets)
  sw x0,-2044(t2)            # mtimecmp_hi = 0 at 0x02000804
  sw x0,-2048(t2)            # mtimecmp_lo = 0 at 0x02000800 -> overdue
  addi a0,x0,1               # trap fires at this boundary
  addi a1,x0,2
handler:
  csrr a0,mcause
  li a1,0x1000
  sw a0,4(a1)                # expect 0x80000007
  csrr a2,mepc
  sw a2,8(a1)
  lui t5,0x2001
  li t6,0xffffffff
  sw t6,-2048(t5)            # push mtimecmp far away
  sw t6,-2044(t5)
  li t4,1
  csrrw x0,0x3ff,t4
