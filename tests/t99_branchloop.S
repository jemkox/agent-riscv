# t99_branchloop.S - store + addi + signed-branch loop with a gp self-check.
# The ISS-timeout workaround is only a run-time note: the original variant looped
# 0x393f8 stores (~1M instructions) and the Python ISS `--pass` run timed out.
# Loop lengths are bounded here (256 iterations), but the Linux-body pattern
# (store + blt) is exercised at BOTH low PC and high PC: the second loop below
# is self-placed at 0x80650000 so the fetch/BTB path for high-PC loop bodies
# stays covered.
    .text
    .globl start
start:
    li gp, 0
    # loop 1: low-PC loop body, 256 stores
    li a3, 0x00001000
    li a4, 0x00001400
loop:
    sw zero, 0(a3)
    addi a3, a3, 4
    blt a3, a4, loop
    li a5, 0x00001400
    bne a3, a5, bad
    # place the high-PC loop body at 0x80650000 (self-modify) and jump there.
    # words are: sw zero,0(a5); addi a5,a5,4; blt a5,a6,H+0; jalr x0,0(ra)
    li t2, 0x80650000
    li t1, 0x0007a023
    sw t1, 0(t2)
    li t1, 0x00478793
    sw t1, 4(t2)
    li t1, 0xff07cce3
    sw t1, 8(t2)
    li t1, 0x00008067
    sw t1, 12(t2)
    # high-PC data also stays under 0x80650000; its 16-bit RAM word alias
    # (0x2000..) cannot collide with the self-placed body alias (0x4000).
    li a5, 0x80648000
    li a6, 0x80648400
    jalr ra, 0(t2)
back:
    li a7, 0x80648400
    bne a5, a7, bad
    li gp, 1
    csrrw x0, 0x3ff, gp
bad:
    li gp, 3
    csrrw x0, 0x3ff, gp
end:
    j end
