#!/usr/bin/env python3
import sys, struct
path = sys.argv[1]
start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
end = int(sys.argv[3]) if len(sys.argv) > 3 else start + 19
with open(path, 'rb') as f:
    if start > 1:
        f.seek((start - 1) * 32)
    for i in range(start, end + 1):
        rec = f.read(32)
        if len(rec) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack('<8I', rec)
        print(i, cyc, f"{pc:08x}", f"{insn:08x}",
              f"rd={rd}", f"wv={wv:08x}", f"st={st}", f"ea={ea:08x}", f"sd={sd:08x}")
