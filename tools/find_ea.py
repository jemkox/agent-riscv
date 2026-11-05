#!/usr/bin/env python3
import struct, sys, re
def usage():
    print("usage: find_ea.py <retire.bin> <addr_hex> [count] [max] [start_rec]")
    sys.exit(2)

if len(sys.argv) < 3:
    usage()
path = sys.argv[1]
target = int(sys.argv[2], 16)
count = int(sys.argv[3]) if len(sys.argv) > 3 else 8
maxrec = int(sys.argv[4]) if len(sys.argv) > 4 else 100000000
start = int(sys.argv[5]) if len(sys.argv) > 5 else 0

with open(path, 'rb') as f:
    f.seek(start * 32)
    n = 0
    for rec_idx in range(start, maxrec):
        buf = f.read(32)
        if len(buf) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack('<8I', buf)
        if (ea & 0xfffffffc) == (target & 0xfffffffc):
            n += 1
            print("%9d %10d %08x %08x rd=%-2u wv=%08x st=%u ea=%08x sd=%08x" % (
                rec_idx, cyc, pc, insn, rd, wv, st, ea, sd))
            if n >= count:
                break
