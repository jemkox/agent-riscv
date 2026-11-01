/* Own crt0 for the Doom ELF testbench (replaces picolibc crt0, whose
   minimal picolibc _cstart spins forever after main instead of exiting).
   Sets sp, clears .bss, runs .init_array constructors, calls main,
   then calls exit -- and exit halts the CPU via the xhalt CSR (0x3ff),
   exactly like programs/m7common.h does.  Linked with -nostartfiles. */
    .section .text
    .globl _start
_start:
    la  sp, __stack
    la  t0, gp_word
    lw  gp, 0(t0)
    la  t0, __bss_start
    la  t1, __bss_size
    beqz t1, bss_done
bss_loop:
    sw  zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -4
    bnez t1, bss_loop
bss_done:
    call __libc_init_array
    call main
    call exit
1:
    j 1b

    .section .rodata
    .align 2
gp_word:
    .word __global_pointer$
