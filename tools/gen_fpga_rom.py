#!/usr/bin/env python3
# gen_fpga_rom.py IN.HEX OUT.SV -- generate cache RAM init include for FPGA build
import sys
words = []
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        words.append(int(line, 16) & 0xffffffff)
out = open(sys.argv[2], "w")
out.write("// auto-generated FPGA cache RAM init include for cache32_fpga\n")
out.write("localparam int FPGA_PROG_WORDS = %d;\n" % len(words))
out.write("initial begin\n")
for i, w in enumerate(words):
    out.write("  ic_lo[%d] = 16'h%04x; ic_hi[%d] = 16'h%04x;\n" % (i, w & 0xffff, i, (w >> 16) & 0xffff))
out.write("end\n")
out.close()
