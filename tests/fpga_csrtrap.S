# fpga_csrtrap.S - FPGA full-CPU ROM program: dynamic trap-CSR writes + a real
# EBREAK trap through mtvec. CSRRS (read-modify-write) makes the mtvec/mie
# register D-inputs genuinely depend on the current register value, so the
# st_mtvec/st_mie flops survive yosys constant folding (no impossible-value
# guards needed). mtvec=60=byte addr of handler (word 15); ebreak at word 14.
  .globl _start
  .option norvc
_start:
  addi x5, x0, 60      # 0: mtvec target
  addi x6, x0, 17      # 1: mie value
  csrrs x7, mtvec, x5  # 2: mtvec <- mtvec|x5
  csrrs x8, mie, x6    # 3: mie <- mie|x6
  add x9, x7, x8       # 4
  slli x10, x9, 2      # 5
  srli x11, x10, 1     # 6
  addi x12, x11, -4    # 7
  xor x13, x12, x9     # 8
  and x14, x13, x5     # 9
  nop                  # 10
  nop                  # 11
  nop                  # 12
  nop                  # 13
  ebreak               # 14: trap -> mtvec (=60 = word 15)
handler:
  csrrs x16, mepc, x0  # 15
  csrrs x17, mcause, x0 # 16
  csrrs x18, mtvec, x0 # 17
  csrrs x19, mie, x0   # 18
  addi x20, x0, 1      # 19
  csrrw x0, 0x3ff, x20 # 20: halt
