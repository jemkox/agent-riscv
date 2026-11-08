# t105: unimplemented CSR numbers must raise illegal-instruction (cause 2), and
# time/timeh (0xc01/0xc81) must read the CLINT mtime (Zicntr view). Directed
# test from the spike brief: 0x14D stimecmp, 0x30C mstateen0, 0x35C mtopi.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  csrrs t0, 0x14d, x0    # stimecmp: unimplemented -> cause 2
  csrrs t0, 0x30c, x0    # mstateen0: unimplemented -> cause 2
  csrrs t0, 0x35c, x0    # mtopi: unimplemented -> cause 2
  csrrs t0, 0x308, x0    # 0x308 is NOT mip on rv32 (mip = 0x344) -> cause 2
  li t3, 4
  bne s0, t3, fail
  # time: read-only view of CLINT mtime; ticks per retired insn.
  csrr t4, 0xc01
  csrr t5, 0xc01
  csrr t6, 0xc81
  li t3, 0
  bne t6, t3, fail
  bge t4, t5, fail       # time must strictly advance between reads
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 2
  bne t2, t3, fail
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  addi s0, s0, 1
  mret
