/* doom/ld.ld -- flat RV32 link for the Doom ELF testbench.
   Text at 0 (loader writes from address 0 upward).
   WAD is loaded by the runner as a separate blob at 0x00C0_0000.
   Heap: after bss up to 0x00B0_0000; stack region 0x00B0_0000..0x00BF_0000
   (grows down from __stack), below the WAD. */
ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text .text.*) *(.srodata .srodata.*) }
  . = 0x00100000;
  .data : {
    __data_start = .;
    __data_source = .;
    *(.data .data.* .rodata .rodata.* .sdata .sdata.*)
  }
  __data_size = . - __data_start;
  __global_pointer$ = __data_start + 0x800;
  __probe_gp__ = __global_pointer$;
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)   /* .sbss too: crt0 must zero it (gametic/maketic live there) */
    . = ALIGN(4);
  }
  __bss_size = . - __bss_start;
  .init_array : {
    __init_array_start = .;
    KEEP (*(.init_array .init_array.*))
    __init_array_end = .;
  }
  .fini_array : {
    __fini_array_start = .;
    KEEP (*(.fini_array .fini_array.*))
    __fini_array_end = .;
  }
  __heap_start__ = .;
  __heap_end__ = 0x00B00000;
  __stack = 0x00BF0000;
  __tls_base = 0;
}
