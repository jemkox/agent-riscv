# t31: A/D bits hardware-update: e7 leaf PA0xA000 flags R|W only. Load sets A;
# store sets D; PTE is re-read via the self-mapped L0 page (VA 0x9000, R|W).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t0, 0x8000
  li t1, 0x2401        # L1[0] -> L0@PA0x9000
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB           # e0 code R|X
  sw t1, 0(t0)
  li t1, 0x40B         # e1 code R|X
  sw t1, 4(t0)
  li t1, 0x24C7        # e9 L0 self page R|W
  sw t1, 36(t0)
  li t1, 0x2807        # e7: (0xA<<10)|R|W|V (no A|D)
  sw t1, 28(t0)
  li t0, 0xA000
  li t1, 0x55AA
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
  li t3, 0x7000        # translated to PA0xA000
  lw t2, 0(t3)         # sets A
  li t4, 0x55AA
  bne t2, t4, fail
  # re-read L0 entry7: VA 0x9000+28 = 0x901C (A only)
  li t3, 0x901C
  lw t2, 0(t3)
  li t4, 0x2847        # A set
  bne t2, t4, fail
  li t3, 0x7000
  li t2, 0xCAFE
  sw t2, 4(t3)         # sets D
  li t4, 0xCAFE
  lw t2, 4(t3)
  bne t2, t4, fail
  li t3, 0x901C
  lw t2, 0(t3)
  li t4, 0x28C7        # A|D set
  bne t2, t4, fail
  j pass
fail:
  li gp, 3
  j done
pass:
  li gp, 1
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 11
  bne t2, t3, fail
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
