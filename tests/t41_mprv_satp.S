# t41: mstatus.MPRV=1 with MPP=S while AT M and satp on: M-mode LOADS/STORES
# translate via the SAME walk using S-mode permission rules (spec MPRV).
# Identity-vs-translated discrimination at the SAME VA0x3000: before satp, M
# store 0xAAAA to VA0x3000 lands at PA0x3000 (identity). L0 leaf VPN3->PA0xC000
# pre-filled 0xBBBB. With satp on + MPRV/MPP=S: lw [0x3000] reads PA0xC000
# (0xBBBB); sw [0x3000] lands at PA0xC000; with MPRV CLEARED the same lw reads
# PA0x3000 (0xAAAA); a plain M identity load of VA0xC000 shows PA0xC000 ==
# 0x2222 (the store went to the leaf PA, not identity 0x3000). No traps used.
# gp=1 on pass, gp=3 fail. All pages >= 0x3000: spike-compatible.
  .globl _start
  .option norvc
_start:
  li gp, 0
  la t1, handler
  csrw mtvec, t1
  # sentinel at identity PA0x3000 (satp still off)
  li t3, 0x3000
  li t1, 0xAAAA
  sw t1, 0(t3)
  # page tables: L1 @PA0x8000 e0 -> L0 @PA0x9000; L0 e3 VPN3 -> PA0xC000
  li t0, 0x8000
  li t1, 0x2401
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0x30C7
  sw t1, 12(t0)
  # pre-fill the LEAF page PA0xC000 (identity M store; VPN3 leaf maps VA0x3000 here)
  li t0, 0xC000
  li t1, 0xBBBB
  sw t1, 0(t0)
  # satp on (MODE=8, root PPN 8 -> PA0x8000), still M
  li t0, 0x80000008
  csrw satp, t0
  # MPRV=1 (bit17), MPP=S (bits 12:11 = 01 -> 0x800)
  li t0, 0x20800
  csrw mstatus, t0
  # (1) MPRV load: translated VPN3 leaf -> PA0xC000 -> 0xBBBB
  lw t2, 0(t3)
  li t4, 0xBBBB
  bne t2, t4, fail
  # (2) MPRV store: lands at the LEAF PA0xC000
  li t1, 0x2222
  sw t1, 0(t3)
  # (3) MPRV load again: reads the updated leaf
  lw t2, 0(t3)
  li t4, 0x2222
  bne t2, t4, fail
  # (4) clear MPRV (keep MPP=S): M data accesses are physical again
  li t0, 0x20000
  csrc mstatus, t0
  lw t2, 0(t3)
  li t4, 0xAAAA
  bne t2, t4, fail
  # (5) identity M load of VA0xC000 sees PA0xC000 == 0x2222 (store landed there)
  li t5, 0xC000
  lw t2, 0(t5)
  li t4, 0x2222
  bne t2, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  li gp, 3
  j done
