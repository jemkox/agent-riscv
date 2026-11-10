#!/usr/bin/env python3
"""Probe spike `time` CSR writes and estimate MTIME_SEED for RTL mt=(retires+SEED)/RATE.
Usage: time_seed_probe.py [spike_commits.log] [rate]
It assumes RTL retire count for an aligned spike instruction is (global_sidx - anchor_sidx).
Anchor is the first spike commit line whose pc == 0x80000000.
"""
import sys, re

path = sys.argv[1] if len(sys.argv) > 1 else "build/linux/logs/spike_deep_commits.log"
rate = int(sys.argv[2]) if len(sys.argv) > 2 else 100

def commit_iter():
    idx = 0
    with open(path, "rb") as f:
        for line in f:
            if not (line.startswith(b"core   0:") and b"(" in line):
                continue
            commit = not line.startswith(b"core   0: 0x")
            if not commit:
                continue
            try:
                p0 = line.index(b"0x") + 2
                p1 = line.index(b" ", p0)
                pc = int(line[p0:p1], 16)
                o1 = line.index(b"(", p1)
                o2 = line.index(b")", o1)
                ins = int(line[o1+1:o2], 16)
            except (ValueError, IndexError):
                idx += 1
                continue
            tail = line[o2+1:].decode(errors="replace")
            ws = re.findall(r"\bx(\d+)\s+0x([0-9a-fA-F]+)", tail)
            rd = wv = None
            if len(ws) == 1:
                rd, wv = int(ws[0][0]), int(ws[0][1], 16)
            yield idx, pc, ins, rd, wv
            idx += 1

it = commit_iter()
anchor = None
for idx, pc, ins, rd, wv in it:
    if pc == 0x80000000:
        anchor = idx
        break
if anchor is None:
    print("anchor 0x80000000 not found")
    sys.exit(2)

samples = []
dbg = []
for idx, pc, ins, rd, wv in it:
    csr = (ins >> 20) & 0xfff
    f3 = (ins >> 12) & 7
    rs1 = (ins >> 15) & 0x1f
    op = ins & 0x7f
    if csr == 0xc01 and len(dbg) < 5:
        dbg.append((idx, pc, hex(ins), csr, f3, rs1, op, rd, wv))
    if csr == 0xc01 and f3 == 2 and rs1 == 0 and op == 0x73 and wv is not None:
        rel = idx - anchor
        lo = wv * rate - rel
        # floor: lo-rate < seed <= lo, but integer seed range is [lo-rate+1, lo]
        samples.append((idx, rel, wv, lo - rate + 1, lo))

samples.sort(key=lambda x: (x[4] + x[3]) // 2)
print("anchor_sidx=%d time_samples=%d" % (anchor, len(samples)))
if samples:
    lo0, hi0 = samples[0][3], samples[0][4]
    print("first10:")
    for idx, rel, val, lo, hi in samples[:10]:
        print("idx=%d rel=%d spike_time=%d seed_range=%d..%d mid=%d" % (idx, rel, val, lo, hi, (lo + hi)//2))
    mid_all = sorted((x[3] + x[4]) // 2 for x in samples)
    print("seed_est_stats min=%d max=%d median=%d" % (mid_all[0], mid_all[-1], mid_all[len(mid_all)//2]))
if dbg:
    print("csr_time_dbg:")
    for t in dbg:
        print("  idx=%d pc=%08x ins=%08x csr=%x f3=%x rs1=%x op=%x rd=%s wv=%s" %
              (t[0], t[1], int(t[2],16), t[3], t[4], t[5], t[6],
               ('-' if t[7] is None else str(t[7])),
               ('-' if t[8] is None else '%08x' % t[8])))
print("idx order first 25 after anchor:")
idx_samples = sorted((x[0], x[1], x[2]) for x in samples)
prev = None
for idx, rel, val in idx_samples[:25]:
    if prev is not None:
        print("gap d_idx=%d d_time=%d rate=%.2f" % (idx-prev[0], val-prev[1], (idx-prev[0]) / max(val-prev[1], 1)))
    print("idx=%d rel=%d spike_time=%d" % (idx, rel, val))
    prev = (idx, val)
