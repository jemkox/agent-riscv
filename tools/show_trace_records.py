#!/usr/bin/env python3
import struct, sys
trace = sys.argv[1]
start = int(sys.argv[2])
end = int(sys.argv[3]) if len(sys.argv) > 3 else start + 1
with open(trace, "rb") as f:
    for i in range(end):
        b = f.read(32)
        if len(b) < 32:
            break
        if i >= start:
            cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", b)
            print(f"n={i+1} cyc={cyc} pc={pc:08x} insn={insn:08x} rd=x{rd:02d} wv={wv:08x} st={st} ea={ea:08x} sd={sd:08x}")
