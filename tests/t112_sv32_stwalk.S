# t112_sv32_stwalk.S — minimal D-walk replay store-data staleness catcher.
# S-mode store to an ABSENT PTE (VPN 0x10); the store's data is produced by the
# ALU op immediately before it (li 0x14059 | or 0xD6 = 0x140df).  The delegated
# S handler maps the identity leaf V|R|W|A|D via the VPN 0x9 mapped view of the
# L2 page, sfence.vma, sret.  The retried store, issued after the D-side walk,
# must write the FRESH 0x140df (the RTL bug wrote the pre-or 0x14059 in t110);
# the reload must read it back.  s1 must be exactly 1.  gp=1 pass, 3 fail.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s1, 0
  # L1@0x8000 (satp 0x80000008) -> L2@0x9000
  li t0, 0x8000
  li t1, 0x2401           # L1[0]: VPN0 -> L2@0x9000
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB              # VPN0 code page (S-only X)
  sw t1, 0(t0)
  li t1, (9<<10)|0xD7     # VPN 0x9 -> the L2 page itself (data view)
  sw t1, (9*4)(t0)
  # push the CLINT compare far away so no spurious STV fires mid-test
  li t0, 0x02000004
  li t1, 0xFFFFFFFF
  sw t1, 0(t0)
  li t1, (1<<13)|(1<<15)
  csrw medeleg, t1
  la t1, handler
  csrw mtvec, t1
  csrw stvec, t1
  li t0, 0x40000          # SUM (same setup as t110; harmless here)
  csrs mstatus, t0
  li t0, 0x80000008
  csrw satp, t0
  # M -> S via mret (MPP=S)
  la t2, sstub
  csrw mepc, t2
  li t0, 0x1800
  csrc mstatus, t0
  li t0, 0x800
  csrs mstatus, t0
  mret
handler:
  csrr t0, scause
  addi s1, s1, 1
  li t4, 15
  beq t0, t4, map
  li t4, 13
  beq t0, t4, map
  j fail
map:
  csrr t6, stval
  srli t6, t6, 12
  andi t6, t6, 0xff
  li t0, 0x9000             # mapped data view of the L2 page (VPN 0x9)
  slli t1, t6, 2
  add t0, t0, t1          # L2 slot for faulting VPN
  lw t1, 0(t0)
  andi t4, t1, 1
  beq t4, x0, mkleaf
  li t4, 0xD6
  or t1, t1, t4           # present entry: grant R|W|A|D
  sw t1, 0(t0)
  j hd
mkleaf:
  slli t1, t6, 10
  li t4, 0xDF
  or t1, t1, t4           # absent: identity leaf V|R|W|A|D
  sw t1, 0(t0)
 hd:
  sfence.vma
  sret
sstub:
  # store whose data was produced by the PREVIOUS alu op, to an unmapped page;
  # value reg t2 and or-operand t5 are handler-safe (handler clobbers t0,t1,t4,t6)
  li t3, 0x10000
  li t2, 0x14059
  li t5, 0xD6
  or t2, t2, t5           # t2 = 0x140df  (fresh from this or)
  sw t2, 0(t3)            # PF15 -> handler maps VPN 0x10 -> retry
  lw t5, 0(t3)            # reload must see the fresh value
  li t4, 0x140df
  bne t5, t4, fail
  li t6, 1
  bne s1, t6, fail
  li gp, 1
  j halt
fail:
  li gp, 3
halt:
  li t4, 1
  csrrw x0, 0x3ff, t4
