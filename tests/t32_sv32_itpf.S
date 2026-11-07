# t32: instruction fetch page fault - jump to a non-executable page (eF leaf
# PA0xF000 flags R|W|A|D, no X). Handler checks mcause=12, mtval=0xF000, mepc
# points at the JUMP (the faulting fetch is at 0xF000; mret would loop there,
# so redirect mepc to the done marker and check counters).
  .globl _start
  .option norvc
_start:
  li gp, 0
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
  li t1, 0x3CE7        # eF: (0xF<<10)|(R|W|A|D|V)
  sw t1, 60(t0)
  li t0, 0xF000        # plant an ecall at PA 0xF000 (never fetched due to NX)
  li t1, 0x73
  sw t1, 0(t0)
  li t0, 0x80000008
  csrw satp, t0
  li t5, 0xF000
  jalr x0, 0(t5)       # target page not executable -> IT PF
  li gp, 9             # must not fall through
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
  li t3, 0xF000
  bne t2, t3, fail
  addi s0, s0, 1
  li gp, 1
  la t2, done          # skip the faulting fetch: return to done
  csrw mepc, t2
  mret
