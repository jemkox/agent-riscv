# t17: a CSR write must use the forwarded rs1 value. Found by the FreeRTOS port: lw t0,0(sp) followed
# by csrw mepc,t0 wrote the OLD t0 (the CSR write took the raw decode-stage register, not the
# forwarded operand). Checked against the ISS trace (each csrr below logs the CSR value).
  .globl _start
  .option norvc
_start:
  li t0, 0x1000
  li t1, 0x12345678
  sw t1, 0(t0)
  li t2, 0x55
  lw t2, 0(t0)
  csrw mscratch, t2         # load-use: needs the loaded value
  csrr a0, mscratch
  li t3, 0x11
  addi t3, t3, 0x22
  csrw mscratch, t3         # ALU result forwarded from MEM
  csrr a1, mscratch
  li t4, 0x40
  addi t4, t4, 1
  nop
  csrw mscratch, t4         # forwarded from WB
  csrr a2, mscratch
  li t5, 0x99
  lw t5, 0(t0)
  csrrs a3, mscratch, t5    # set-bits form with a loaded operand
  csrr a4, mscratch
  li t6, 1
  li gp, 1; csrrw x0, 0x3ff, t6
