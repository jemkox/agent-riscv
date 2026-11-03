/* crt0 for the stock FreeRTOS RISC-V port demo.
   Like doom/crt0_rv32.S but also wires the CPU to the stock portASM trap
   model: mtvec -> freertos_risc_v_trap_handler, MTIE enabled in mie and
   mstatus.MIE (MPP is forced to M-mode by hardware).  Linked with -nostartfiles. */
    .section .text
    .globl _start
_start:
    la  sp, __stack
    la  t0, gp_word
    lw  gp, 0(t0)
    la  t0, freertos_risc_v_trap_handler
    csrw mtvec, t0
    li  t1, 0x80
    csrw mie, t1                         /* MTIE (interrupt number 7) */
    li  t1, 8
    csrs mstatus, t1                     /* MIE on; MPP stays M-mode (forced) */
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

    .section .bss
    .align 8
irq_stack:
    .space 2048
    .globl __freertos_irq_stack_top
    .set __freertos_irq_stack_top, irq_stack + 2048

    .section .rodata
    .align 2
gp_word:
    .word __global_pointer$
