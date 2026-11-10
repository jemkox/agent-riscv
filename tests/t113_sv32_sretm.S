# t113_sv32_sretm.S — pins the SPIKE-PINNED RV32 SPP convention (pinned spike 1.1.1-dev
# and upstream rv32mi/illegal; the priv-2022-draft has the OPPOSITE polarity):
# mstatus.SPP=1 <=> sret returns to S (set on trap from S); SPP clear => sret returns to U.
# P1: from M, sepc=p1, SPP SET -> must land at S (csrw satp legal at S; at U it traps
#     and, under the draft polarity, the handler re-sret loops back to U -> no markers).
# P2: from S, sepc=p2, SPP CLEAR -> must land at U (csrw satp -> cause 2 delegated to
#     S handler; handler SETS SPP so its sret returns to S; retry at S is legal).
# Expected: exactly one delegated trap (s5==1), s1==1, s6==1 -> gp=1; else gp=3.
        .globl _start
        .option norvc
_start:
  la t1, h
  csrw stvec, t1
  csrw mtvec, t1
  li t0, 4                  # delegate cause 2 to S
  csrw medeleg, t0
  la t2, p1
  csrw sepc, t2
  li t2, 0x100
  csrs sstatus, t2          # SPP set -> per priv-spec sret returns to S
  sret
p1:
  csrw satp, x0             # legal at S (draft polarity would trap here and loop)
  addi s1, s1, 1
  la t2, p2
  csrw sepc, t2
  li t2, 0x100
  csrc sstatus, t2          # SPP clear -> per priv-spec sret returns to U
  sret
p2:
  csrw satp, x0             # at U: cause 2 -> h -> sret to S -> retry legal
  addi s6, s6, 1
  li t4, 1
  bne s5, t4, fail
  bne s1, t4, fail
  bne s6, t4, fail
  li gp, 1
  j halt
h:
  addi s7, s7, 1
  li t0, 1
  or s5, s5, t0
  li t2, 0x100
  csrs sstatus, t2          # SPP set -> handler sret returns to S (retry at S)
  sret
fail:
  li gp, 3
halt:
  li t4, 1
  csrw 0x3ff, t4
