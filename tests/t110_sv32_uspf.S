# t110: U-mode data page faults delegated to S (Linux/BusyBox shape).
# U load/store/AMO to: (a) absent PTE (V=0), (b) present leaf W=0, (c) D=0
# (walker heals A/D, no fault), (d) load from X-only page, (e) AMO to W=0 page.
# (a),(b),(d),(e) -> S handler with scause 15/13, stval=faulting VA, sepc=fault
# pc; handler maps/permits the PTE + sfence.vma, sret RETRY must succeed. Handler
# counts faults in s1 (expect 4). U checks every loaded/stored value and the
# D bit of the healed PTE via a mapped view of the L2 page. gp=1 on pass, 3 on fail.
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
  li s1, 0
  # L1@0x8000 (satp 0x80000008) -> L2@0x9000
  li t0, 0x8000
  li t1, L1_ENTRY
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, (MMU_CODE_VPN<<10)|CODE_FLAGS              # code page S-only
  sw t1, ((MMU_CODE_VPN&0xFF)*4)(t0)
  li t1, ((MMU_CODE_VPN+1)<<10)|(CODE_FLAGS|0x10)   # U-code page: +U bit
  sw t1, (((MMU_CODE_VPN+1)&0xFF)*4)(t0)
  li t1, (9<<10)|0xD7        # VPN 0x9 -> the L2 page itself (data view)
  sw t1, (9*4)(t0)
  li t1, (0x30<<10)|0xD3      # VPN0x30 present R|A|D|V (W=0)
  sw t1, (0x30*4)(t0)
  li t1, (0x40<<10)|0x57      # VPN0x40 present R|W|A|V (D=0)
  sw t1, (0x40*4)(t0)
  li t1, (0x25<<10)|0x59      # VPN0x25 present X|A|V (R=0): load fault (PA 0x25000 in RAM window)
  sw t1, (0x25*4)(t0)
  li t1, (6<<10)|0xD3      # VPN0x60 present R|A|D|V (W=0): AMO store fault
  sw t1, (6*4)(t0)
  # seed physical RAM values (satp off, M physical)
  li t0, ((MMU_CODE_VPN+0x20)<<12)   # case (a) page must hold 0x7777 (mmu: 0x20000)
  li t1, 0x7777
  sw t1, 0(t0)
  li t0, 0x30000
  li t1, 0x6666
  sw t1, 0(t0)
  li t0, 0x6000
  li t1, 0x0010
  sw t1, 0(t0)
  # push the CLINT compare far away so no spurious STV fires mid-test
  li t0, 0x02000004
  li t1, 0xFFFFFFFF
  sw t1, 0(t0)
  li t1, (1<<13)|(1<<15)
  csrw medeleg, t1
  la t1, handler
  csrw mtvec, t1
  csrw stvec, t1
  li t0, 0x40000          # SUM: S handler may read the U-flagged L2 view
  csrs mstatus, t0
  li t0, 0x80000008
  csrw satp, t0
  # M -> S via mret (MPP=S), then S -> U via sret with SPP clear (per priv spec: clear => U)
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
  or t1, t1, t4           # absent: identity leaf V|R|W|X|A|D
  sw t1, 0(t0)
 hd:
  sfence.vma
  sret
sstub:
  # S-origin DPF: S-store to an unmapped page at S priv; the delegated handler maps
  # it and sret (priv spec: trap-from-S SETS SPP) must return to S.  The
  # following satp write is legal in S but illegal in U (cause 2 -> j fail), so a
  # buggy sret-to-U cannot pass this test.
  li t3, 0x10000
  li t2, 0x0020
  sw t2, 0(t3)             # S-priv store PF 15 -> handler -> retry at S (t2 survives handler)
  lw t5, 0(t3)
  li t4, 0x0020
  bne t5, t4, fail
  li t6, 0x80000008
  csrw satp, t6            # legal in S; would trap if sret had returned to U
  la t2, ustart
  csrw sepc, t2
  li t0, 0x100             # per priv spec: CLEAR => sret returns to U
  csrc sstatus, t0
  sret
  .p2align 12             # U code lands on its own U-flagged page (VPN +1)
ustart:
  # (a) load from absent PTE: PF13; handler maps identity RW|A|D; retry loads
  li t3, ((MMU_CODE_VPN+0x20)<<12)
  lw t2, 0(t3)
  li t4, 0x7777
  bne t2, t4, fail
  li t2, 0x3333
  sw t2, 0(t3)            # now permitted: clean store
  lw t4, 0(t3)
  bne t4, t2, fail
  # (b) present W=0 page: load ok, store PF15, handler sets W|A|D, retry
  li t3, 0x30000
  lw t4, 0(t3)
  li t5, 0x6666
  bne t4, t5, fail
  sw t2, 0(t3)            # PF15 -> handler -> retry
  lw t4, 0(t3)
  bne t4, t2, fail
  # (c) present D=0 page: walker hardware-heals, no fault
  li t3, 0x40000
  sw t2, 0(t3)
  lw t4, 0(t3)
  bne t4, t2, fail
  # healed PTE (L2 slot 0x40 via VPN 0x9 data view) must now carry D bit 0x80
  li t3, 0x9000
  lw t4, (0x40*4)(t3)
  li t5, 0x80
  and t4, t4, t5
  beq t4, x0, fail
  # (d) load from X-only page (VPN 0x25, PA in RAM window): PF13; handler grants R|W|A|D; retry loads 0
  li t3, 0x25000
  lw t4, 0(t3)            # PF13
  bne t4, x0, fail
  # (e) U AMO to W=0 page: PF15; handler grants W; retry amoadd 0x0010+0x3333
  li t3, 0x6000
  amoadd.w t6, t2, 0(t3)  # t6 = old (0x0010)
  lw t4, 0(t3)
  li t5, 0x3343
  bne t4, t5, fail
  # fault count via handler (s1): load@a, store@b, load@d, amo@e, S-store@f = 5
  li t4, 5
  bne s1, t4, fail
  li gp, 1
  j halt
fail:
  li gp, 3
halt:
  li t4, 1
  csrrw x0, 0x3ff, t4
