# t46: pinned spike implements LEGACY mhpmcounter3..31 CSRs 0xB03-0xB1F as
# machine-level CSRs that read 0 / ignore writes (not counters, not a trap).
# OpenSBI probes mhint3 (0xB03) while still in M; a strict "unimplemented CSR"
# decode traps there and diverges from the pin.  U/S gating: t47_sys_hints_priv.
  .globl _start
  .option norvc
_start:
  .word 0xB0302873            # csrrs x16, mhint3(0xB03), x0 -> x16 = 0
  bne x16, x0, fail
  li t0, 0x2A5
  .word 0xB03298F3            # csrrw x17, mhint3(0xB03), t0 -> x17 = old (0); write ignored
  bne x17, x0, fail
  .word 0xB1F027F3            # csrrs x15, 0xB1F (top hint), x0 -> x15 = 0
  bne x15, x0, fail
  .word 0xB0302873            # re-read after the write: hints stay stateless 0
  bne x16, x0, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
  j .
