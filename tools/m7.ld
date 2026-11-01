ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text .text.*) }
  . = 0x10000;
  .data : { *(.data .data.* .rodata) }
  . = 0x18000;
  .bss : { *(.bss .bss.*) *(COMMON) }
  . = 0x21000;
  __stack_top = .;
}
