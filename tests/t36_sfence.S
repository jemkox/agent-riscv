# t36: remap + SFENCE.VMA. e8 leaf maps VA0x8000 -> PA0xA000 (value 0x55AA).
# Load ok. Then rewrite e8 to PA0xB000 (PA0xB000 holds 0x1234) through the
# self-mapped L0 page, sfence.vma, reload -> must see 0x1234 (post-flush).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t0, 0x8000
  li t1, 0x2401
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB
  sw t1, 0(t0)
  li t1, 0x40B
  sw t1, 4(t0)
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
  # spec: satp translates S/U only -> enter S via mret (MPP=S)
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
  # remap: store new PTE (PA0xB000 leaf) into e8 via self page (0x9000+32=0x9020)
  li t3, 0x9020
  li t2, 0x2CC7        # (0xB<<10)|R|W|A|D|V
  sw t2, 0(t3)         # store to W page ok
  .word 0x12000073       # sfence.vma zero,zero (real SYSTEM encoding, bits[31:25]=0x12>>1)
  lw t2, 0(t3)         # read back the new PTE (stale/flush both ok: PTE page identity)
  lw t2, 0(t3)         # (kept: exercises TLB again)
  li t3, 0x8000
  lw t2, 0(t3)         # post-flush: must follow new mapping
  li t4, 0x1234
  bne t2, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
