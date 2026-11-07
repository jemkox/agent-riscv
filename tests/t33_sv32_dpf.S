# t33: load/store page faults. eD: pte=0 (invalid) -> load VA0xD000 PF13 mtval
# 0xD000. eC leaf PA0x2000 flags R|X|A|D (no W): store VA0xC000 -> PF15 mtval
# 0xC000. Handler counts and skips; both must fire exactly once (s0=2), then a
# clean load from a valid page proves recovery.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x8000
  li t1, 0x2401
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, 0xB
  sw t1, 0(t0)
  li t1, 0x40B
  sw t1, 4(t0)
  li t1, 0x24C7
  sw t1, 36(t0)
  li t1, 0x28C7        # eA: (0xA<<10)|R|W|A|D|V
  sw t1, 40(t0)
  li t1, 0x28CB        # eC: (0xA<<10)|R|X|A|D|V (no W)
  sw t1, 48(t0)
  li t0, 0xA000
  li t1, 0x7777
  sw t1, 0(t0)
  li t0, 0x80000008
  csrw satp, t0
  # invalid page load
  li t3, 0xD000
  lw t2, 0(t3)         # load PF13; falls through after handler skips
  nop
  # store into read-only page
  li t3, 0xC000        # maps PA 0xA000 R|X no W
  li t2, 0xBAD
  sw t2, 0(t3)         # store PF15
  # recovery: good load
  li t3, 0xA000        # eA identity leaf
  lw t2, 0(t3)
  li t4, 0x7777
  bne t2, t4, fail
  li t4, 2
  bne s0, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 13
  beq t2, t3, ok
  li t3, 15
  beq t2, t3, ok
  j fail
ok:
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
