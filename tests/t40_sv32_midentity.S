# t40: satp on while STILL AT M: identity data access wins over a page-table
# mapping of the SAME VA to a different PA (spec: satp translates S/U only;
# M data is untranslated unless MPRV). L1@PA0x8000 e0 -> L0@PA0x9000.
# L0 e3: VPN3 -> PA0xC000 (R|W|A|D|V=0xC7). L0 e4: VPN4 -> PA0xD000 (0xC7).
# M stores BEFORE satp: [0x3000]=0x1111 (identity PA of VA0x3000), [0xD000]=0x2222.
# With satp on at M: lw VA0x3000 MUST be 0x1111 (identity), sw [0x3004]=0x3333
# then lw back = 0x3333, and PA0xD000 MUST still hold 0x2222 (no translated store
# ever happened at M). gp=1 on pass, gp=3 on fail; any unexpected trap fails.
# All pages >= 0x3000 so the same test runs on spike (RAM spec -m0x2000:...).
  .globl _start
  .option norvc
_start:
  li gp, 0
  la t1, handler
  csrw mtvec, t1
  # page tables (identity M stores, satp still off)
  li t0, 0x8000
  li t1, 0x2401        # L1 e0: (9<<10)|V -> L0 @PA0x9000
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0x30C7        # e3: (0xC<<10)|R|W|A|D|V -> PA0xC000
  sw t1, 12(t0)
  li t1, 0x34C7        # e4: (0xD<<10)|R|W|A|D|V -> PA0xD000
  sw t1, 16(t0)
  # fill: identity page VA0x3000/PA0x3000 and translated target PA0xD000
  li t0, 0x3000
  li t1, 0x1111
  sw t1, 0(t0)
  li t0, 0xD000
  li t1, 0x2222
  sw t1, 0(t0)
  # satp on (MODE=8, root PPN 0x8 -> PA0x8000), still M
  li t0, 0x80000008
  csrw satp, t0
  # M data access MUST be identity: PA0x3000 content, not PA0xD000+0
  li t3, 0x3000
  lw t2, 0(t3)
  li t4, 0x1111
  bne t2, t4, fail
  # M store stays identity, read back
  li t0, 0x3004
  li t1, 0x3333
  sw t1, 0(t0)
  li t3, 0x3004
  lw t2, 0(t3)
  li t4, 0x3333
  bne t2, t4, fail
  # the PTE target PA was NEVER touched by an M access
  li t3, 0xD000
  lw t2, 0(t3)
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
