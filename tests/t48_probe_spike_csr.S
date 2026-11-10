# t48_probe_spike_csr: probe pinned-spike behaviour of 0xBxx counter-ish CSRs
# at M (used to extend the RTL/ISS CSR pin for boot: kernel executes 0xB83).
# Run with spike -l --log-commits; read the x31/x30 values from the log.
  .globl _start
  .option norvc
_start:
  .word 0xB0302FF3          # csrrs x31, 0xB03, x0
  .word 0xB0002FF3          # csrrs x31, 0xB00, x0
  .word 0xB0202FF3          # csrrs x31, 0xB02, x0
  .word 0xB8002FF3          # csrrs x31, 0xB80, x0
  .word 0xB8202FF3          # csrrs x31, 0xB82, x0
  .word 0xB8302FF3          # csrrs x31, 0xB83, x0
  .word 0xB9F02FF3          # csrrs x31, 0xB9F, x0
  .word 0xB0102FF3          # csrrs x31, 0xB01, x0
  .word 0xB2002FF3          # csrrs x31, 0xB20, x0
  .word 0xB8102FF3          # csrrs x31, 0xB81, x0
  .word 0x30202FF3          # csrrs x31, 0x302, x0 (scratch)
  li x28, 0x555
  .word 0xB83E1073          # csrrw x0, 0xB83, x28 (write at M)
  halt:
  li gp, 1
  csrrw x0, 0x3ff, gp
  j .
