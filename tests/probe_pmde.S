.globl _start
_start:
 li t0, 0xFFFFFFFF
 csrw medeleg, t0
 csrr t1, medeleg
 ecall
 li a7,93
 li a0,0
 ecall
