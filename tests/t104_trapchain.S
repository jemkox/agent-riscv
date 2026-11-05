# t104_trapchain.S - trap-entry store->load chain check (Linux handler pattern).
# mscratch = slot base 0x1000. Slot [8] pre-filled with 0xdeadbeef.
# At trap, sp = 0x1234. Handler stores sp to 8(x6),12(x6), then lw sp,8(x6).
# ISA: load MUST return the just-stored 0x1234 (RAW, distance 2).
# Pass halts gp=1; fail (stale load) halts gp=3.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t1, 0x1000
  li t2, 0xdeadbeef
  sw t2, 8(t1)
  li sp, 0x1234
  csrw mscratch, t1
  la t0, handler
  csrw mtvec, t0
  ebreak
  # after mret we land here: unexpected (handler halts first)
  li gp, 5
  j end
handler:
  csrrs t1, mscratch, zero
  sw sp, 8(t1)
  sw sp, 12(t1)
  lw sp, 8(t1)
  li t3, 0x1234
  beq sp, t3, ok
  li gp, 3
  csrrw x0, 0x3ff, gp
ok:
  li gp, 1
  csrrw x0, 0x3ff, gp
end:
  j end
