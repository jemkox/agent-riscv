/* link_spike.ld - link at 0x20000 (VPN 0x20,0x21). Spike 1.1 reserves [0,0x2000)
   for its boot/stack devices and refuses to load ELF segments there, so the
   MMU tests are rebuilt at this origin; -DMMU_CODE_VPN=0x20 makes the identity
   code-page leaves follow the link. Run with RAM -m0x2000:0x1FE000. */
ENTRY(_start)
SECTIONS {
  . = 0x20000;
  .text : { *(.text .text.*) }
  . = 0x21000;
  .data : { *(.data .data.* .rodata) }
}
