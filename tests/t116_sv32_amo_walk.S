# t116: atomic on the last word before an ITLB walk.  sfence.vma empties the
# TLB; AMO at VA0xff8 executes while fetching VA0x1000 needs a page walk.
# amoadd.w +1 must apply exactly once (0x1234 -> 0x1235), not +2.
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
  li t1, 0x2401          # root e0 -> L0 @PA0x9000
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, (MMU_CODE_VPN<<10)|CODE_FLAGS
  sw t1, (MMU_CODE_VPN&0xFF)*4(t0)
  li t1, ((MMU_CODE_VPN+1)<<10)|CODE_FLAGS
  sw t1, ((MMU_CODE_VPN+1)&0xFF)*4(t0)
  li t1, (4<<10)|0xC7   # VPN4 -> PA0x4000, data
  sw t1, 16(t0)
  li t0, 0x4000
  li t1, 0x1234
  sw t1, 0(t0)          # seed data (physical, satp still off)
  li t0, 0x80000008
  csrw satp, t0
  li a0, 0x4000
  li t1, 1
  j sfence
  .org 0xff4
sfence:
  sfence.vma
  .org 0xff8
amo:
  amoadd.w a2, t1, 0(a0)
  nop
  .org 0x1000
  li t5, 0x1234
  bne a2, t5, fail
  lw t3, 0(a0)
  li t4, 0x1235
  bne t3, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
