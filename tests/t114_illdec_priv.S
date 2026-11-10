# t114: U/S-mode instruction-decode pin for the SFENCE.VMA privilege check.
# sw/lw with imm offset 288 and a bne with imm 288 have insn bits[31:25]==0b0001001
# and bits[11:7]==0 (imm fields) but opcode != 1110011: they are LEGAL at S with
# mstatus.TVM=1 and at U; ONLY the real sfence.vma (opcode 1110011, f3=0) may
# trap cause 2: at S with TVM set and at U always.  A priv check that tests
# only bits[31:25]+[11:7] misdecodes those legal insns as SFENCE (BusyBox SIGILL).
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s2, 0
  la t1, handler
  csrw mtvec, t1
  la t1, s_phase
  csrw mepc, t1
  li t0, 0x100800         # MPP=S (0x800) + TVM bit20 (0x100000)
  csrw mstatus, t0
  mret
s_phase:                  # S with TVM=1: legal mem/branch encodings, then sfence
  li x15, 0x8000
  li x9, 0xABCD
  sw x9, 288(x15)         # insn bits[31:25]=0b0001001, bits[11:7]=0 -> legal store
  lw x10, 288(x15)        # same bit pattern -> legal load
  bne x10, x9, 288        # bne imm=+288: same bit pattern -> legal branch
  sfence.vma              # S + TVM -> cause 2 (1st trap)
s_phase2:
  sfence.vma              # S, TVM cleared by handler -> legal, no trap
  ecall                   # cause 9 from S (2nd trap) -> handler enters U
u_phase:                  # U (satp=0, bare)
  li x15, 0x9000
  li x9, 0x5678
  sw x9, 288(x15)         # must NOT trap at U
  lw x10, 288(x15)        # must NOT trap at U
  bne x10, x9, 288        # must NOT trap at U
  sfence.vma              # U -> cause 2 (3rd trap)
  j bad_trap              # unreachable
handler:
  csrr t2, mcause
  addi s2, s2, 1
  li t3, 9
  beq t2, t3, to_u        # ecall from S
  li t3, 2
  bne t2, t3, bad_trap
  csrr t4, mtval
  li t5, 0x12000073
  bne t4, t5, bad_trap    # a misdecoded sw/lw/bne shows up as cause2 tval=insn -> FAIL
  li t3, 1
  beq s2, t3, s_resume    # 1st: sfence at S with TVM
  li t3, 3
  beq s2, t3, d_resume    # 3rd: sfence at U
  j bad_trap
s_resume:
  la t6, s_phase2
  csrw mepc, t6
  li t0, 0x800            # MPP=S, TVM cleared
  csrw mstatus, t0
  mret
to_u:
  la t6, u_phase
  csrw mepc, t6
  csrw mstatus, x0        # MPP=U
  mret
d_resume:
  la t6, done_m
  csrw mepc, t6
  li t0, 0x1800           # MPP=M
  csrw mstatus, t0
  mret
bad_trap:
  li gp, 3
  j halt
done_m:
  li t4, 3
  bne s2, t4, halt        # exactly the three pinned traps happened
  li gp, 1
halt:
  li t4, 1
  csrrw x0, 0x3ff, t4
  j .
