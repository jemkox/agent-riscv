# t44: sip/sie are spec-restricted views of mip/mie: reads are masked to the
# S-accessible bits, writes to sie update the single mie storage (S-owned
# bits only) and writes to sip update mip.SSIP (bit1, delegated). Kernel
# needs exactly this: OpenSBI sets mip.SSIP for SBI IPIs and the kernel
# clears it with csrci sip,2; without sip state the pending SSIP never
# clears and the boot spins in idle-IRQ loops.
  .globl _start
  .option norvc
_start:
  li gp, 0
  li t0, 0x22
  csrw mideleg, t0          # delegate SSIP(bit1) + STIP(bit5) to S
  li t0, 0xA0
  csrw mie, t0              # mie: bit5 (deleg. STIP enable) + bit7 (MTIP, M-owned)
  csrr t1, sie
  li t2, 0x20               # sie read: bit7 (M-owned) hidden
  bne t1, t2, fail
  li t0, 0x02
  csrw sie, t0              # sie write updates mie's S bits: bit5 := 0, bit1 := 1
  li t2, 0x82               # mie = (0xA0 & ~0x22) | 0x02: bit7 untouched
  csrr t1, mie
  bne t1, t2, fail
  csrr t1, sie
  li t2, 0x02
  bne t1, t2, fail
  li t0, 0x22
  csrw mip, t0              # mip (0x344 ABI number): pending SSIP + STIP
  csrr t1, sip
  andi t1, t1, 0x22         # sip = mip & mideleg
  li t2, 0x22
  bne t1, t2, fail
  csrci sip, 2              # clear SSIP through the sip view: delegated -> must stick
  csrr t1, mip
  andi t1, t1, 0x22         # SSIP cleared in mip itself (shared storage)
  li t2, 0x20
  bne t1, t2, fail
  csrr t1, sip
  andi t1, t1, 0x22
  bne t1, t2, fail
  li t0, 0x08               # MSIP (bit3) is not delegated: sip write must not touch it
  csrs sip, t0
  csrr t1, mip
  andi t1, t1, 0x8          # MSIP (live CLINT) still 0; MTIP may be live in spike
  li t2, 0
  bne t1, t2, fail
  csrr t1, sip
  andi t1, t1, 0x22
  li t2, 0x20
  bne t1, t2, fail
  li t0, 0x20
  csrc sie, t0              # clear delegated STIP enable via sie: mie bit5 already 0
  li t2, 0x82
  csrr t1, mie              # sie ops touched only the S-owned bits
  bne t1, t2, fail
  csrr t1, sie
  li t2, 0x02
  bne t1, t2, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
