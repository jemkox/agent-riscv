# t38: SUM=1 positive rule (the L6 RTL/ISS fix): S-mode with mstatus.SUM=1 runs
# from the identity X|R|U|A|D|V code page holding the whole blob (VA/PA 0x0-0xFF
# stores an R|W|U|A|D page (VA 0x5000 -> PA 0x15000): fetch, load and store must
# all be LEGAL (a6=0 retired, s0=0, gp=1). With the old unconditional S-faults-
# U rule the first sblock fetch raised PF12 and sblock's a6 write never retired.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, done            # a stray fault lands on the self-check path
  csrw mtvec, t1
  li t0, 0x8000
  li t1, 0x2401          # L1[VPN1=0] -> L0 at PPN 9 (PA 0x9000), interior V+A
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xDB            # vpn0 0: code identity PA 0 X|R|U|A|D|V (blob at 0)
  sw t1, 0(t0)
  li t1, 0x24C7          # vpn0 9: L0 self page R|W A D V
  sw t1, 36(t0)
  li t1, 0x54C7          # vpn0 5: VA 0x5000 -> PA 0x15000, R|W|U|A|D|V
  sw t1, 20(t0)
  li t0, 0x15000
  li t1, 0x6161
  sw t1, 0(t0)           # U-page payload (bare M store, pre-satp)
  li t0, 0x80000008
  csrw satp, t0
  la t2, sblock
  csrw mepc, t2
  li t0, 0x1800          # clear MPP
  csrc mstatus, t0
  li t0, 0x800           # MPP=S
  csrs mstatus, t0
  li t0, 0x40000         # SUM=1 before mret
  csrs mstatus, t0
  mret                   # enter S on the identity U code page
sblock:
  li a6, 0               # mmucheck sblock 0
  li t3, 0x5000          # U data page: load with SUM=1 must be legal
  lw t2, 0(t3)
  li t4, 0x6161
  bne t2, t4, fail
  li t4, 0x2323          # store with SUM=1 must be legal
  sw t4, 0(t3)
  lw t2, 0(t3)
  bne t2, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
  j done
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
