# t48: spike 1.1.1-dev vendor ID CSRs 0xf11..0xf14 (legacy numbering:
# mvendorid/marchid/mimpid/mhartid).  Pinned against the boot commit log
# build/linux/logs/spike_deep_commits.log: mvendorid=0 (line 10752211 x9=0),
# marchid=5 (lines 31161360/31219514: x15=0x00000005 at 0x8000e344), mimpid=0
# (line 31220106 x15=0), mhartid=0 (lines 5/825870).  Reads are constants;
# OpenSBI (fw_jump banner) probes them before entering S.
  .globl _start
  .option norvc
_start:
  .word 0xF11027F3            # csrrs x15, mvendorid(0xF11), x0 -> 0 (spike)
  bne x15, x0, fail
  li t0, 5
  .word 0xF1202773            # csrrs x14, marchid(0xF12), x0 -> 5 (spike boot log)
  bne x14, t0, fail
  .word 0xF13026F3            # csrrs x13, mimpid(0xF13), x0 -> 0 (spike)
  bne x13, x0, fail
  .word 0xF1402673            # csrrs x12, mhartid(0xF14), x0 -> 0 (spike)
  bne x12, x0, fail
  .word 0xF12025F3            # csrrs x11, marchid, x0 -> 5 again (stateless constant)
  bne x11, t0, fail
  li t1, 0xF0000000
  .word 0x7A102573            # csrrs x10, 0x7A1 (spike smask-family) -> constant
  bne x10, t1, fail
  li t1, 0x0100807C
  .word 0x7A402573            # csrrs x10, 0x7A4 (spike smask-family) -> constant
  bne x10, t1, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
  j .
