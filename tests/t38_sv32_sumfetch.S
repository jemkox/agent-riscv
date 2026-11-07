# t38: SUM=1 is NO rescue for an S instruction fetch of a U page (spec access-
# control table; arch-test Sv_sv32_upage_mstatus_sum_set_Smode faults the jalr
# even with sstatus.SUM set; RTL/ISS revert of the "SUM enables S fetch" rule).
# S with mstatus.SUM=1 jumps (badjal) to the X|R|U page VA 0x4000 -> PA 0x14000:
# PF12 delegated to stvec (S handler): scause==12, stval==0x4000, sepc==0x4000
# (the faulting FETCH address; the jalr itself retires), a6 pinned 12 (# mmucheck
# sdone c), handler sets sepc=afterit and srets ->
# S resumes in the identity code page, gp=1 (SUM=1 still rescues the LOAD/STORE
# of U pages in t35 - that rule is untouched).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw stvec, t1
  li t0, 0x1000          # medeleg[12]: page-fetch fault -> S (S-mode handler)
  csrw medeleg, t0
  li t0, 0x8000
  li t1, 0x2401          # L1[VPN1=0] -> L0 at PPN 9 (PA 0x9000), interior V+A
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB             # vpn0 0: code identity PA 0, X|R (A set by walker)
  sw t1, 0(t0)
  li t1, 0x40B           # vpn0 1: code PA 0x1000, X|R (tail pages)
  sw t1, 4(t0)
  li t1, 0x24C7          # vpn0 9: L0 self page R|W A D
  sw t1, 36(t0)
  li t1, 0x501B          # vpn0 4: VA 0x4000 -> PA 0x14000, X|R|U (no A/D yet)
  sw t1, 16(t0)
  li t0, 0x14000
  li t1, 0x6161
  sw t1, 0(t0)           # U-page payload (bare M store, pre-satp)
  li t0, 0x80000008
  csrw satp, t0
  la t2, sblock
  csrw mepc, t2
  li t0, 0x1800
  csrc mstatus, t0       # clear MPP
  li t0, 0x800           # MPP=S
  csrs mstatus, t0
  li t0, 0x40000         # SUM=1 before mret: must NOT rescue an S fetch
  csrs mstatus, t0
  mret                   # enter S on the identity X|R code page
sblock:
  li t5, 0x4000          # U page (X|R|U): S fetch with SUM=1 -> PF12
badjal:
  jalr x0, 0(t5)         # jalr retires; the FETCH at 0x4000 faults (sepc=stval=0x4000)
afterit:
  li gp, 1               # resumed after the faulting jump (S)
  j done
fail:
  li gp, 3
  j done
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, scause        # S-mode handler via stvec (medeleg[12] delegated)
  li t3, 12
  bne t2, t3, fail
  csrr t2, sepc          # faulting fetch VA (the jalr retired; epc = fetch addr)
  li t3, 0x4000
  bne t2, t3, fail
  csrr t2, stval         # faulting VA reported in stval (MMU IT fault)
  li t3, 0x4000
  bne t2, t3, fail
  addi s0, s0, 1         # the SUM-rescued-fetch bug would land here w/ no fault
  li a6, 12              # mmucheck sdone c
sdone:
  la t2, afterit         # skip the faulting jump, resume in S
  csrw sepc, t2
  sret
