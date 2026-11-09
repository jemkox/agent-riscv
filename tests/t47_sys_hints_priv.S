# t47: hint CSRs 0xB03-0xB1F are LEGACY mhpmcounter3..31 (machine-level) in
# pinned spike: reads 0 / ignored writes but ONLY at M.  At S and U the access
# must trap: cause 2, mtval=insn, no writeback.  Without this pin a wrongly
# permissive (all-privilege) gate would be invisible to the boot probe.
  .globl _start
  .option norvc
_start:
  li gp, 0
  la t1, handler
  csrw mtvec, t1
  # ---- S phase: enter S via mret, read 0xB1F (must trap cause 2) ----
  la t1, s_phase
  csrw mepc, t1
  li t0, 0x800            # mstatus MPP=S
  csrw mstatus, t0
  mret
s_phase:
  li x15, 0x777           # sentinel: trap must NOT write back
  .word 0xB1F027F3        # csrrs x15, 0xB1F (top hint), x0 at S -> trap
  j fail
resume1:
  li t4, 0x777
  bne x15, t4, fail       # sentinel intact -> trapping insn never wrote back
  # ---- U phase: enter U via mret, write 0xB03 (must trap cause 2) ----
  la t1, u_phase
  csrw mepc, t1
  csrw mstatus, x0        # mstatus MPP=U
  mret
u_phase:
  li x17, 0x666           # sentinel: trap must NOT write back
  .word 0xB03298F3        # csrrw x17, mhint3(0xB03), t0 at U -> trap
  j fail
resume2:
  li t4, 0x666
  bne x17, t4, fail
  li gp, 1
  j done
fail:
  li gp, 3
  j done
handler:                  # M handler: cause 2 + mtval=insn, dispatch by insn
  csrr t2, mcause
  li t3, 2
  bne t2, t3, bad_trap
  csrr t4, mtval
  li t5, 0xB1F027F3       # S-phase insn word
  beq t4, t5, s_hit
  li t5, 0xB03298F3       # U-phase insn word
  beq t4, t5, u_hit
  j bad_trap
s_hit:
  la t6, resume1
  j resume_m
u_hit:
  la t6, resume2
resume_m:
  csrw mepc, t6
  li t0, 0x1800           # mstatus MPP=M
  csrw mstatus, t0
  mret
bad_trap:
  li gp, 3
  j done
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
  j .
