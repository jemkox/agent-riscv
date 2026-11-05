#!/usr/bin/env python3
import sys, struct
path, lo, hi = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0)
f = open(path, 'rb')
n = 0
while True:
    b = f.read(32)
    if len(b) < 32:
        break
    n += 1
    cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack('<8I', b)
    if lo <= cyc <= hi:
        print('%d cyc=%d pc=%08x insn=%08x rd=%2d wv=%08x st=%d ea=%08x sd=%08x' % (n, cyc, pc, insn, rd, wv, st, ea, sd))
