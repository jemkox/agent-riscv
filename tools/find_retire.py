#!/usr/bin/env python3
import sys, struct, mmap, os
if len(sys.argv) < 3:
    print("usage: find_retire.py <cpu_retire.bin> <pc_hex> [count] [context] [start_rec]")
    raise SystemExit
path = sys.argv[1]
want = int(sys.argv[2], 16)
count = int(sys.argv[3]) if len(sys.argv) > 3 else 5
ctx = int(sys.argv[4]) if len(sys.argv) > 4 else 20
start = int(sys.argv[5]) if len(sys.argv) > 5 else 1
needle = struct.pack('<I', want)
with open(path, 'rb') as f:
    idx = 0
    ring = []
    while True:
        rec = f.read(32)
        if len(rec) < 32:
            break
        idx += 1
        if idx < start:
            continue
        pc = struct.unpack_from('<I', rec, 4)[0]
        ring.append((idx, rec))
        if len(ring) > ctx + 3:
            ring.pop(0)
        if pc == want and count > 0:
            for ridx, r in ring:
                cyc, pc2, insn, rd, wv, st, ea, sd = struct.unpack('<8I', r)
                print(f"{ridx:10d} {cyc:12d} {pc2:08x} {insn:08x} rd={rd} wv={wv:08x} st={st} ea={ea:08x} sd={sd:08x}")
            print('---')
            count -= 1
            if count == 0:
                break
