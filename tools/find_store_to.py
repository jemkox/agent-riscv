#!/usr/bin/env python3
import struct, sys
trace = sys.argv[1]
addr = int(sys.argv[2], 16)
maxn = int(sys.argv[3]) if len(sys.argv) > 3 else 700000
with open(trace, "rb") as f:
    for n in range(maxn):
        b = f.read(32)
        if len(b) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", b)
        if st and (ea & ~3) == (addr & ~3):
            print(f"store n={n+1} cyc={cyc} pc={pc:08x} insn={insn:08x} ea={ea:08x} sd={sd:08x} st={st}")
            for d in (-2, -1, 0, 1, 2):
                if d == 0:
                    continue
                f.seek((n + d) * 32, 0)
                c = f.read(32)
                if len(c) < 32:
                    continue
                c2, p2, i2, r2, w2, s2, e2, d2 = struct.unpack("<8I", c)
                print(f"  n={n+d+1} cyc={c2} pc={p2:08x} insn={i2:08x} rd=x{r2:02d} wv={w2:08x} st={s2} ea={e2:08x} sd={d2:08x}")
            break
