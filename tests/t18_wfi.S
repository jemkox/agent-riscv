# t18: WFI both paths (L1).  With an MTI pending (mtimecmp=0, mie.MTIE, mstatus
# MIE) the wfi traps AT the wfi pc (mepc = wfi address) with mcause 0x8000_0007.
# The handler reads mip (0x308, bit7 set), pushes mtimecmp far away and mrets ->
# the SAME wfi re-executes, now with no IRQ pending, and retires as a NOP: the
# following csrr mcycle pair proves counters tick across it, mip now reads 0.
# WFI = 0x00100073 (SYSTEM f3=0 csr 0x100); spelled .word to dodge gas quirks.
  .globl _start
  .option norvc
_start:
  li t0,8                    # mstatus.MIE
  csrrw x0,mstatus,t0
  la t1,thdl
  csrrw x0,mtvec,t1
  li t5,0x80                 # mie.MTIE
  csrrw x0,0x304,t5
  lui t2,0x2001              # CLINT page base
  sw x0,-2044(t2)            # mtimecmp_hi = 0
  sw x0,-2048(t2)            # mtimecmp_lo = 0 -> overdue
  lui a1,0x2
  addi a1,a1,-2048           # scratch 0x1800
  csrr t3,0x308              # mip pre-trap (bit7 set)
  sw t3,0(a1)
  .word 0x10000073           # wfi: pending -> MTI traps here
  j after                    # skip the handler (only falls in after NOP path)
thdl:
  csrr t3,mcause
  sw t3,4(a1)                # expect 0x80000007
  csrr t5,mepc
  sw t5,8(a1)                # expect wfi pc
  csrr t6,0x308              # mip inside handler (still pending)
  sw t6,12(a1)
  lui t2,0x2001
  li t5,0xFFFFFFFF
  sw t5,-2048(t2)            # push mtimecmp far away
  sw t5,-2044(t2)
  mret                       # back to wfi; now not pending -> NOP retire
after:
  csrr t3,mcycle             # mcycle before re-executed wfi
  sw t3,16(a1)
  .word 0x10000073           # wfi: not pending -> retires as NOP
  csrr t1,mcycle
  sw t1,20(a1)               # expect > value at 0x1810
  csrr t2,0x308              # mip now clear
  sw t2,24(a1)
  li t4,1
  csrrw x0,0x3ff,t4
