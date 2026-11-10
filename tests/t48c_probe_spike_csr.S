# t48c: probe spike behaviour of machine-level CSRs 0x300-0x30f,0x310,0x311,
# 0x30c-0x30f,0x3ff. Each csrrs x31 stores the old value; illegal -> exception.
  .globl _start
  .option norvc
_start:
  .word 0x30702FF3          # csrrs x31, 0x307
  .word 0x30802FF3          # csrrs x31, 0x308
  .word 0x30902FF3          # csrrs x31, 0x309
  .word 0x30A02FF3          # csrrs x31, 0x30A
  .word 0x30B02FF3          # csrrs x31, 0x30B
  .word 0x30F02FF3          # csrrs x31, 0x30F
  .word 0x31102FF3          # csrrs x31, 0x311
  halt:
  li gp, 1
  csrrw x0, 0x3ff, gp
  j .
