# t34: Sv32 megapages. L1[0] leaf PPN=0 (aligned 4 MiB, R|W|X+A|D): code and
# data run identity through the megapage. L1[1] leaf PPN=1 is NOT 4 MiB aligned
# -> jump to VA 0x0040_0000 must raise IT PF (mtval=0x0040_0000); handler
# redirects to done.
  .globl _start
  .option norvc
_start:
  li gp, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x8000
  li t1, 0xCF          # L1[0]: PPN0 leaf R|W|X|A|D|V
  sw t1, 0(t0)
  li t1, 0x4CF         # L1[1]: PPN1 leaf (misaligned megapage)
  sw t1, 4(t0)
  li t0, 0xA000
  li t1, 0x3F3F
  sw t1, 0(t0)
  li t0, 0x80000008
  csrw satp, t0
  li t3, 0xA000        # inside megapage, identity
  lw t2, 0(t3)
  li t4, 0x3F3F
  bne t2, t4, fail
  li t2, 0x1234
  sw t2, 4(t3)
  lw t2, 4(t3)
  li t4, 0x1234
  bne t2, t4, fail
  li t5, 0x400000
  jalr x0, 0(t5)       # misaligned megapage -> IT PF
  li gp, 9
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
  li t3, 12
  bne t2, t3, fail
  csrr t2, mtval
  li t3, 0x400000
  bne t2, t3, fail
  addi s0, s0, 1
  li gp, 1
  la t2, done
  csrw mepc, t2
  mret
