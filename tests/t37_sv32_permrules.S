# t37: permission-rule pins against the spec (rv32 § access-control rules).
# e6: W-only page (R=0): M load w/o MXR -> PF13; handler sets MXR and re-execs
# the load -> returns 0x6161.  e7: R-only page (W=0): M store -> PF15, handler
# skips the store (mepc+4).  R|W page load still ok.  s0 must be 2 (both faults
# seen with the right mtval), a6 pins the fault count; gp=1.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x8000
  li t1, 0x2401          # L1[VPN1=0] -> L0 at PPN 9 (interior: perms 0, V+A+D)
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB             # vpn0 0: code PA0 identity R|X (A set by walker)
  sw t1, 0(t0)
  li t1, 0x40B           # vpn0 1: code PA0x1000 R|X A
  sw t1, 4(t0)
  li t1, 0x24C7          # vpn0 9: L0 self page R|W A D
  sw t1, 36(t0)
  li t1, 0x30C7          # vpn0 5 (VA0x5000) -> PA0xC000 R|W A D
  sw t1, 20(t0)
  li t1, 0x30C5          # vpn0 6 (VA0x6000) -> PA0xC000 W-only A D (R=0!)
  sw t1, 24(t0)
  li t1, 0x30C3          # vpn0 7 (VA0x7000) -> PA0xC000 R-only A D (W=0!)
  sw t1, 28(t0)
  li t0, 0xC000
  li t1, 0x6161
  sw t1, 0(t0)
  li t0, 0x80000008
  csrw satp, t0
  # spec: satp translates S/U only -> enter S via mret (MPP=S)
  la t2, swalk
  csrw mepc, t2
  li t0, 0x1800
  csrc mstatus, t0
  li t0, 0x800
  csrs mstatus, t0
  mret
swalk:
  # 1) W-only load at M w/o MXR -> PF13; handler sets MXR, mret retries
  li t3, 0x6000
  lw t2, 0(t3)
  li t4, 0x6161
  bne t2, t4, fail
  # 2) store to R-only page -> PF15; handler skips the faulting store
  li t3, 0x7000
  li t2, 0x1234
  sw t2, 0(t3)
  # 3) R|W page load still ok
  li t3, 0x5000
  lw t2, 0(t3)
  li t4, 0x6161
  bne t2, t4, fail
  li a6, 2               # mmucheck afterf 2
afterf:
  li t4, 2
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
  li t3, 13
  beq t2, t3, d13
  li t3, 15
  beq t2, t3, d15
  j fail
d13:
  csrr t2, mtval
  li t3, 0x6000
  bne t2, t3, fail
  addi s0, s0, 1
  li t0, 0x80000         # MXR (rv32 env encoding.h)
  csrs mstatus, t0
  mret                 # retry the same load with MXR now set
d15:
  csrr t2, mtval
  li t3, 0x7000
  bne t2, t3, fail
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
