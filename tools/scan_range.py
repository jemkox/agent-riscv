#!/usr/bin/env python3
import struct, sys
trace = sys.argv[1]
lo = int(sys.argv[2], 16)
hi = int(sys.argv[3], 16)
maxn = int(sys.argv[4]) if len(sys.argv) > 4 else 700000
with open(trace, "rb") as f:
    for n in range(maxn):
        b = f.read(32)
        if len(b) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", b)
        if lo <= ea <= hi:
            print(f"n={n+1} cyc={cyc} pc={pc:08x} insn={insn:08x} rd=x{rd:02d} wv={wv:08x} st={st} ea={ea:08x} sd={sd:08x}")
