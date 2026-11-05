#!/usr/bin/env python3
import struct, sys
def usage():
    print("usage: dump_rec.py <retire.bin> <start_rec> <count>")
    sys.exit(2)
if len(sys.argv) < 4:
    usage()
path = sys.argv[1]
start = int(sys.argv[2])
count = int(sys.argv[3])
with open(path, 'rb') as f:
    f.seek(start * 32)
    for rec_idx in range(start, start + count):
        buf = f.read(32)
        if len(buf) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack('<8I', buf)
        print("%9d %10d %08x %08x rd=%-2u wv=%08x st=%u ea=%08x sd=%08x" % (
            rec_idx, cyc, pc, insn, rd, wv, st, ea, sd))
