# t99_branchloop.S - short store + addi + signed branch loop with a gp self-check.
    .text
    .globl start
start:
    li gp, 0
    li a3, 0x00001000
    li a4, 0x00001010
loop:
    sw zero, 0(a3)
    addi a3, a3, 4
    blt a3, a4, loop
    li a5, 0x00001010
    bne a3, a5, bad
    li gp, 1
    csrrw x0, 0x3ff, gp
bad:
    li gp, 3
    csrrw x0, 0x3ff, gp
end:
    j end
