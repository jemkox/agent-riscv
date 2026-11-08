# t42: atomics through the page table (satp + MPRV, MPP=S). lr.w VA0x3000 old=0x1111; sc.w
# succeeds rd=0 and 0x2222 is visible; lr 0x3004 + successful sc.w (0x3333 visible) then a SECOND
# sc.w at the same address with NO LR between - the spec-mandated must-fail: rd=1 and the word
# keeps 0x3333 (our SC-clears-reservation + no-reservation-SC-fails rule; both goldens implement
# it; a plain-store between LR/SC is NOT pinned - a spurious failure is legal and t19 pins OUR
# clear-on-store choice); amoadd.w (t0) rd=old 0x2222 mem=0x2229; amoadd.w into an R|A|V (no W)
# amoadd.w faults PF15 mtval 0x4000 (handler counts exactly 1, skips), then a load sees
# 0x6666 UNCHANGED (the faulting AMO stored nothing). gp=1.
/* MMU_CODE_VPN: 0 for tests/link.ld; 0x20 for the spike build (see t30). */
#ifndef MMU_CODE_VPN
#define MMU_CODE_VPN 0
#endif
#ifndef L1_ENTRY
#define L1_ENTRY 0x2401
#endif
#ifndef CODE_FLAGS
#define CODE_FLAGS 0xB
#endif
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x3000
  li t1, 0x1111
  sw t1, 0(t0)
  li t1, 0x5555
  sw t1, 4(t0)
  li t0, 0x4000
  li t1, 0x6666
  sw t1, 0(t0)
  li t0, 0x8000       # root table: entry VPN[1]=0 -> L0@PA0x9000
  li t1, L1_ENTRY
  sw t1, 0(t0)
  li t0, 0x9000       # L0 table
  li t1, (MMU_CODE_VPN<<10)|CODE_FLAGS
  sw t1, (MMU_CODE_VPN&0xFF)*4(t0)
  li t1, ((MMU_CODE_VPN+1)<<10)|CODE_FLAGS
  sw t1, ((MMU_CODE_VPN+1)&0xFF)*4(t0)
  li t1, 0xCC7        # vpn0 3 -> PA0x3000 | R|W|A|D|V
  sw t1, 12(t0)
  li t1, 0x1043      # vpn0 4 -> PA0x4000 | R|A|V (W=0)
  sw t1, 16(t0)
  li t0, 0x80000008
  csrw satp, t0
  li t0, 0x1800
  csrc mstatus, t0
  li t0, 0x20800     # MPRV + MPP=S
  csrs mstatus, t0
  li t0, 0x3000
  lr.w t3, 0(t0)
  li t4, 0x1111
  bne t3, t4, fail
  li t1, 0x2222
  sc.w t5, t1, 0(t0)
  bnez t5, fail      # sc must SUCCEED (rd=0)
  lw t3, 0(t0)
  bne t3, t1, fail   # 0x2222 written by sc
  li t2, 0x3004
  lr.w t3, 0(t2)
  li t4, 0x5555
  bne t3, t4, fail     # lr old value pinned
  li a5, 0x3333
  sc.w t5, a5, 0(t2)   # first SC succeeds and CLEARS the reservation
  bnez t5, fail
  lw t3, 0(t2)
  bne t3, a5, fail     # 0x3333 visible
  li a6, 0x7777
  sc.w t6, a6, 0(t2)   # spec-mandated: no reservation -> SC MUST fail rd=1
  li t4, 1
  bne t6, t4, fail
  lw t3, 0(t2)
  bne t3, a5, fail     # second SC wrote NOTHING (word keeps 0x3333)
  li a1, 7
  amoadd.w a2, a1, 0(t0)
  li t4, 0x2222      # rd = old value
  bne a2, t4, fail
  lw t3, 0(t0)
  li t4, 0x2229
  bne t3, t4, fail
  li t0, 0x1800      # re-arm data mode: mret leaves MPP=M (sail); pin eff=S for the
  csrc mstatus, t0   # RO-leaf probe so the PF15 fires in EVERY mret-MPP semantics
  li t0, 0x20800     # MPRV + MPP=S
  csrs mstatus, t0
  li t0, 0x4000
  li a1, 1
  amoadd.w a2, a1, 0(t0)   # read-only leaf -> PF15, handler skips
  nop
  li t0, 0x1800      # post-mret re-arm: spike mrets with MPP=00, our/sail restore MPP=M;
  csrc mstatus, t0   # pin eff=S here so the tail load runs translated in EVERY model
  li t0, 0x20800     # MPRV + MPP=S
  csrs mstatus, t0
  li t0, 0x4000
  lw t3, 0(t0)
  li t4, 0x6666      # faulting AMO stored NOTHING
  bne t3, t4, fail
  li t2, 1
  bne s0, t2, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t4, 15
  bne t2, t4, fail
  csrr t3, mtval
  li t4, 0x4000
  bne t3, t4, fail
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
