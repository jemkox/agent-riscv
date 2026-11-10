  .globl _start
  .option norvc
# Directed distance-1 forwarding for Zicntr read-only CSRs (time/timeh/cycle/instret).
# Linux-boot symptom: `csrr a5,time` (0xC01) followed by `sw a5,0(s2)` stored 0:
# the CSR producer's forwarded result came from the latched idex_cs_old, which the
# idex_old block did not model for these CSRs. Every consumer (store data, ALU
# operand, branch) must see EXACTLY the value written to rd, even though mtime
# changes every cycle. Pinned spike/ISS retire the CSR and hand one value to all.
_start:
  li x28, 0x1000            # .data page base (link.ld)
  li x30, 0                 # error accumulator

  # --- A: csrr time; sw forwarded data; reload; must equal rd itself
  csrr x15, 0xc01
  sw x15, 0(x28)
  lw x16, 0(x28)
  bne x15, x16, fail

  # --- B: csrr time; distance-1 ALU use (copy through alu)
  csrr x17, 0xc01
  addi x18, x17, 0
  bne x17, x18, fail

  # --- C: timeh (high half of the same live mtime)
  csrr x19, 0xc81
  sw x19, 4(x28)
  lw x20, 4(x28)
  bne x19, x20, fail
  # store high half a second time: value may have advanced, but the value
  # stored must equal what the FOLLOWING lw-back of rd shows for consistency
  csrr x19, 0xc81
  sw x19, 8(x28)
  lw x20, 8(x28)
  bne x19, x20, fail

  # --- D: cycle (Zicntr 0xC00)
  csrr x21, 0xc00
  sw x21, 12(x28)
  lw x22, 12(x28)
  bne x21, x22, fail

  # --- E: instret (Zicntr 0xC02)
  csrr x23, 0xc02
  sw x23, 16(x28)
  lw x24, 16(x28)
  bne x23, x24, fail

  # --- F: distance-1 branch operand after csrr
  csrr x25, 0xc00
  xori x26, x25, 0
  bne x25, x26, fail

  # --- G: distance 2 must keep working (regfile write, not forwarding)
  csrr x27, 0xc01
  addi x4, x0, 1            # filler between producer and consumer
  addi x29, x27, 0
  bne x27, x29, fail

  # --- H: store, then lw same word, compared back to rd (the user's exact shape)
  csrr x5, 0xc01
  sw x5, 20(x28)
  lw x6, 20(x28)
  bne x5, x6, fail

  li gp, 1
  csrrw x0, 0x3ff, gp       # pass marker
fail:
  csrrw x0, 0x3ff, x0       # fail

.data
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
