# t99_branchloop.S — store + addi + signed branch loop, matching Linux body.
    .text
    .globl start
start:
    li a3, 0x80650000
    li a4, 0x806893f8
loop:
    sw zero, 0(a3)
    addi a3, a3, 4
    blt a3, a4, loop
    li x30, 1
    csrrw x0, 0x3ff, x30
