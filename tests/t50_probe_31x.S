# t50_probe_31x: probe spike CSR numbers 0x310-0x31f individually.
  .globl _start
  .option norvc
_start:
  .word 0x31002FF3
  .word 0x31102FF3
  .word 0x31202FF3
  .word 0x31302FF3
  .word 0x31402FF3
  .word 0x31502FF3
  .word 0x31602FF3
  .word 0x31702FF3
  .word 0x31802FF3
  .word 0x31902FF3
  .word 0x31A02FF3
  .word 0x31B02FF3
  .word 0x31C02FF3
  .word 0x31D02FF3
  .word 0x31E02FF3
  .word 0x31F02FF3
  halt:
  li gp, 1
  csrrw x0, 0x3ff, gp
  j .
