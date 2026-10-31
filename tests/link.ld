ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text .text.*) }
  . = 0x1000;
  .data : { *(.data .data.* .rodata) }
}
