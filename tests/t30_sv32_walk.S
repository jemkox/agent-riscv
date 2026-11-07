# t30: Sv32 walk - identity code pages + non-identity data page for load/store.
# Tables are built by stores BEFORE satp is set (identity mode), then paging is
# on. L1@PA0x8000, L0@PA0x9000. Code pages vpn0 0,1 identity (X|R). Data page
# VA 0x8000 -> PA 0xA000 (R|W, A|D preset).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x1800
  csrw mstatus, t0
  # L1 root @PA 0x8000: entry0 non-leaf V -> L0@PA 0x9000
  li t0, 0x8000
  li t1, 0x2401        # (9<<10)|1
  sw t1, 0(t0)
  # L0 @PA 0x9000
  li t0, 0x9000
  li t1, 0xB           # e0: ppn0 R|X|V (code)
  sw t1, 0(t0)
  li t1, 0x40B         # e1: (1<<10)|R|X|V (code)
  sw t1, 4(t0)
  li t1, 0x24C7        # e9: (9<<10)|R|W|A|D|V (page 0x9000 readable)
  sw t1, 36(t0)
  li t1, 0x28C7        # e8: (0xA<<10)|R|W|A|D|V: VA0x8000 -> PA0xA000
  sw t1, 32(t0)
  # data value at PA 0xA000 (identity before paging)
  li t0, 0xA000
  li t1, 0x55AA
  sw t1, 0(t0)
  # enable Sv32: satp = mode|ppn8
  li t0, 0x80000008
  csrw satp, t0
  # load via translated VA 0x8000 -> PA 0xA000
  li t3, 0x8000
  lw t2, 0(t3)
  li t4, 0x55AA
  bne t2, t4, fail
  # store through translated VA 0x8004 -> PA 0xA004, read back
  li t2, 0xBEEF
  sw t2, 4(t3)
  lw t2, 4(t3)
  li t4, 0xBEEF
  bne t2, t4, fail
  j pass
fail2:
  li gp, 5
  j done
pass:
  li gp, 1
  j done
fail:
  li gp, 3
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
