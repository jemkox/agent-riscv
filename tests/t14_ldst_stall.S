  .globl _start
  .option norvc
# Directed load-use -> dependent-store cases (stall fix: cache MM hookup
# uses idex_valid && !stall so the store issue is not lost/duplicated).
_start:
  lui x28, 0x1          # data base 0x1000
  addi x30, x0, 32
  sw x30, 16(x28)       # [0x1010] = 0x20 sentinel
  addi x29, x0, 8
  # case 1: lw, dependent sw uses the LOADED value (derived) as address
  lw x27, 20(x28)       # x27 = 0x80000000 (data word5)
  srli x27, x27, 31     # x27 = 1
  slli x27, x27, 5      # x27 = 32
  add x26, x28, x27     # x26 = 0x1020
  sw x29, 0(x26)        # [0x1020] = 8
  lw x25, 0(x26)        # x25 = 8 (load from the dependent-store address)
  # case 2: store right after dependent alu op of a load
  lw x24, 4(x28)        # x24 = 0x12345678 (data word1)
  addi x23, x24, 0
  sw x23, 36(x28)       # [0x1024] = 0x12345678
  lw x22, 36(x28)
  # case 3: back-to-back store of a loaded VALUE
  lw x21, 8(x28)        # x21 = 0xFFFFFFFF
  sw x21, 40(x28)       # [0x1028] = 0xFFFFFFFF
  lw x20, 40(x28)
  # load into zero then dependent store (reg0 must not be written, store fires)
  lw x0, 12(x28)
  sw x20, 44(x28)       # [0x102C] = 0xFFFFFFFF
  lw x19, 44(x28)
  # store-to-load forwarding, then dependent store of the forwarded value
  addi x18, x0, 0x5A5
  sw x18, 48(x28)
  lw x17, 48(x28)
  addi x16, x17, 0
  sw x16, 52(x28)       # [0x1034] = 0x5A5
  lw x15, 52(x28)
  # two independent stores back to back
  addi x14, x0, 123
  sw x14, 56(x28)
  sw x14, 60(x28)
  lw x13, 56(x28)
  lw x12, 60(x28)
  # overwrite the sentinel with a dependent store (loaded value source)
  lw x11, 16(x28)       # x11 = 0x20 (the sentinel itself, load-use)
  addi x11, x11, 1      # x11 = 0x21
  sw x11, 16(x28)       # [0x1010] = 0x21, exactly once (no double store)
  lw x10, 16(x28)
  addi x30,x0,1; csrrw x0,0x3ff,x30
.data
.word 0xDEADBEEF
.word 0x12345678
.word 0xFFFFFFFF
.word 0x000000FF
.word 0x7FFFFFFF
.word 0x80000000
.word 0x0
.word 0x0
