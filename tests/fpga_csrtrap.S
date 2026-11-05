# fpga_csrtrap.S - FPGA full-CPU ROM program: dynamic trap-CSR writes + a real
# EBREAK trap through mtvec. minstret is read into x5/x6 before the trap, so
# the mtvec/mie writes use live counter state instead of constants folded from
# the baked ROM. The first write sees minstret=0, so executed mtvec is 60.
  .globl _start
  .option norvc
_start:
  csrrs x5, minstret, x0 # 0: read live instruction counter
  addi x5, x5, 60        # 1: mtvec target (dynamic D-input; 60 at runtime)
  csrrw x0, mtvec, x5    # 2: write mtvec
  csrrs x6, minstret, x0 # 3
  addi x6, x6, 17        # 4: small mie value (dynamic; no timer bit early)
  csrrw x0, mie, x6      # 5
  nop                    # 6
  nop                    # 7
  nop                    # 8
  nop                    # 9
  nop                    # 10
  nop                    # 11
  nop                    # 12
  nop                    # 13
  ebreak                 # 14: trap -> mtvec (=60 = word 15)
handler:
  csrrs x16, mepc, x0    # 15
  csrrs x17, mcause, x0  # 16
  csrrs x18, mtvec, x0   # 17
  csrrs x19, mie, x0     # 18
  addi x20, x0, 1        # 19
  csrrw x0, 0x3ff, x20   # 20: halt
