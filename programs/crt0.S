.section .text
.globl _start
.globl __stack_top
_start:
  la sp, __stack_top
  call main
  li t4, 0
  csrrw x0, 0x3ff, t4
loop:
  j loop
