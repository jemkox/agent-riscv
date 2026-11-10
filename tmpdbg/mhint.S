.option norvc
.text
.globl _start
_start:
csrrs x1, 0xb03, x0
csrrw x2, 0xb03, x1
csrrs x3, 0xb02, x0
csrrs x4, 0xb1e, x0
li a7,93
ecall
