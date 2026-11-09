# t45: SFENCE.VMA variants on t36's layout:
#   (a) sfence.vma with rs1 = VA (the 4K remap reload, same as t36 but rs1 form)
#   (b) satp WRITE (satp -> 0 while still in S): the very next load must follow
#       the NEW bare/identity mapping even without any sfence (TLB flush on satp
#       write).  PA0x8000 identity holds the L1 entry 0x2401; the stale TLB would
#       still return 0x1234 (PA0xB000).
# All addresses >= 0x1000 (spike-compatible). Same tables as t36.
/* MMU_CODE_VPN: 0 for tests/link.ld builds; 0x20 for the spike build (like t30). */
#ifndef MMU_CODE_VPN
#define MMU_CODE_VPN 0
#endif
#ifndef CODE_FLAGS
#define CODE_FLAGS 0xB
#endif
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t0, 0x8000
  li t1, 0x2401        # e0 -> L0 @PA0x9000
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, (MMU_CODE_VPN<<10)|CODE_FLAGS
  sw t1, (MMU_CODE_VPN&0xFF)*4(t0)
  li t1, ((MMU_CODE_VPN+1)<<10)|CODE_FLAGS
  sw t1, ((MMU_CODE_VPN+1)&0xFF)*4(t0)
  li t1, 0x24C7        # e9 self R|W
  sw t1, 36(t0)
  li t1, 0x28C7        # e8 -> PA0xA000
  sw t1, 32(t0)
  li t0, 0xA000
  li t1, 0x55AA
  sw t1, 0(t0)
  li t0, 0xB000
  li t1, 0x1234
  sw t1, 0(t0)
  li t0, 0x80000008
  csrw satp, t0
  la t2, swalk
  csrw mepc, t2
  li t0, 0x1800
  csrc mstatus, t0
  li t0, 0x800
  csrs mstatus, t0
  mret
swalk:
  li t3, 0x8000
  lw t2, 0(t3)
  li t4, 0x55AA
  bne t2, t4, fail
  # remap: store new PTE (PA0xB000 leaf) into e8 via self page (0x9020)
  li t3, 0x9020
  li t2, 0x2CC7        # (0xB<<10)|R|W|A|D|V
  sw t2, 0(t3)
  .word 0x120E0073     # sfence.vma t3,x0  (rs1 = VA form; SYSTEM encoding)
  li t3, 0x8000
  lw t2, 0(t3)         # post-flush: must follow new mapping
  li t4, 0x1234
  bne t2, t4, fail
  # satp write flush: disable paging in S; next load follows identity (0x2401),
  # a stale TLB entry for VA0x8000 would still yield 0x1234.
  li t0, 0
  csrw satp, t0
  li t3, 0x8000
  lw t2, 0(t3)
  li t4, 0x2401
  bne t2, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
