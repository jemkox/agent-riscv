#!/usr/bin/env python3
# Dump binary retire records from build/linux/cpu_retire.bin around a record index.
# usage: boot_trace_dump.py TRACE N [BEFORE] [AFTER]
import struct, sys

trace_path = sys.argv[1]
n0 = int(sys.argv[2])
before = int(sys.argv[3]) if len(sys.argv) > 3 else 20
after = int(sys.argv[4]) if len(sys.argv) > 4 else 10

with open(trace_path, "rb") as f:
    if n0 > before:
        f.seek((n0 - before - 1) * 32)
        # align to the requested window start; records are 32 bytes
    else:
        f.seek(0)
    start = max(1, n0 - before)
    for i in range(start, start + before + after + 1):
        rec = f.read(32)
        if len(rec) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", rec)
        fields = f"cyc={cyc:08x} pc={pc:08x} insn={insn:08x} rd=r{rd} wv={wv:08x} st={st} ea={ea:08x} sd={sd:08x}"
        print(f"n={i} {fields}")
