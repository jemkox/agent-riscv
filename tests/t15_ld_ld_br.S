  .globl _start
  .option norvc
# Two loads, then a branch using both: the first load's value is forwarded from WB while the
# second load stalls the branch, and must be kept through the stall (Doom R_InitTextures bug).
_start:
  lui x28, 0x1          # data base 0x1000
  addi x5, x0, 0x222
  sw x5, 0(x28)         # [0x1000] = 0x222 (offset)
  lui x6, 0x2
  addi x6, x6, 0x412
  sw x6, 4(x28)         # [0x1004] = 0x2412 (maxoff)
  addi x10, x0, 0       # x10 = error count
  addi x7, x0, 0        # stale value in the first load's register
  lw x7, 0(x28)         # x7 = 0x222
  lw x8, 4(x28)         # x8 = 0x2412
  blt x8, x7, bad1      # 0x2412 < 0x222 is false
  j ok1
bad1:
  addi x10, x10, 1
ok1:
  addi x7, x0, 0x7ff    # stale value
  lw x7, 0(x28)         # x7 = 0x222
  lw x8, 4(x28)
  bge x7, x8, bad2      # 0x222 >= 0x2412 is false
  j ok2
bad2:
  addi x10, x10, 2
ok2:
  addi x9, x0, 0
  lw x9, 0(x28)
  lw x8, 4(x28)
  add x11, x8, x9       # ALU op on both: x11 = 0x2634
  addi x10, x10, 0
  addi x30,x0,1; li gp, 1; csrrw x0,0x3ff,x30
.data
.word 0
