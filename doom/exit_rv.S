/* _exit halts the CPU the same way M7 programs do: a write of 1 to
   the xhalt test CSR (0x3ff), then spin.  (ecall is NOT a halt --
   since M5 ecall traps to mtvec.) */
    .section .text
    .globl _exit
_exit:
    li  t4, 1
    csrrw x0, 0x3ff, t4
1:
    j 1b
