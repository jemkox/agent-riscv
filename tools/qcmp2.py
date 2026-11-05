#!/usr/bin/env python3
# Compare QEMU exec-trace TB-start sequence vs CPU retire pc sequence at
# block granularity, skipping trap-handler regions on both sides.
import sys, struct, re
from collections import deque

qlog, cbin, kbin = sys.argv[1], sys.argv[2], sys.argv[3]
VEC = 0x80473db4
REG_END = 0x80474030

pat = re.compile(r'\[([0-9a-f]{8})/([0-9a-f]{16})/')
starts = []
with open(qlog) as f:
    for line in f:
        m = pat.search(line)
        if m:
            p = int(m.group(2), 16)
            if not (VEC <= p < REG_END):
                starts.append(p)
print('qemu TB starts=%d' % len(starts))

startset = set(starts)
fcpu = open(cbin, 'rb')

n = 0
recent = deque(maxlen=10)
k = 0
resync = 0
ignored = 0
report = []
while True:
    rec = fcpu.read(12)
    if len(rec) < 12:
        break
    cyc, pc, insn = struct.unpack('<III', rec)
    if VEC <= pc < REG_END:
        continue
    n += 1
    if k < len(starts) and starts[k] == pc:
        recent.append(pc)
        k += 1
        continue
    j = -1
    for w in range(k, min(k + 60, len(starts))):
        if starts[w] == pc:
            j = w
            break
    if j >= 0:
        resync += j - k + 1
        k = j + 1
        continue
    if pc in recent:
        # CPU looping extra iterations over a small loop body; skip until
        # the expected QEMU pc appears, if the whole run stays inside the body.
        fcpu_seek_ok = False
        buf = []
        while True:
            r2 = fcpu.read(12)
            if len(r2) < 12:
                break
            c2, p2, i2 = struct.unpack('<III', r2)
            if VEC <= p2 < REG_END:
                continue
            if p2 == starts[k]:
                fcpu_seek_ok = True
                pc, cyc, insn = p2, c2, i2
                break
            if p2 not in recent:
                break
            buf.append((c2, p2, i2))
        if fcpu_seek_ok:
            ignored += 1 + len(buf)
            if VEC <= pc < REG_END:
                continue
            if k < len(starts) and starts[k] == pc:
                recent.append(pc)
                k += 1
                continue
            # fall through with new pc
            if pc in recent:
                ignored += 1
                continue
            if pc not in startset:
                ignored += 1
                continue
            report.append((n, cyc, pc, k))
            if len(report) >= 10:
                break
            continue
    if pc not in startset:
        ignored += 1      # chained TB or loop-iter repeat QEMU ran unlogged
        continue
    report.append((n, cyc, pc, k))
    if len(report) >= 10:
        break

print('scanned=%d resync=%d ignored=%d k_used=%d/%d' % (n, resync, ignored, k, len(starts)))
for t, cyc, pc, kk in report[:10]:
    print('CPUONLY n=%d cyc=%d pc=%08x k=%d nextQ=%08x' % (t, cyc, pc, kk, starts[kk] if kk < len(starts) else 0))
