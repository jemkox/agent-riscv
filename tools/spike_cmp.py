#!/usr/bin/env python3
# Compare our retire trace (build-linux/mmu3/cpu_retire.bin) against a Spike
# --log-commits log (tools/spike_boot_log.sh). Streams both 1:1 after syncing to
# the first retire. Reports the first divergences in (pc, insn) and, when Spike
# shows an xREG writeback, in the written value too (CSR/device values may
# legitimately differ - inspect the printed context, don't assume).
import struct, sys, re

retire_f = sys.argv[1]
log_f = sys.argv[2]
maxrep = int(sys.argv[3]) if len(sys.argv) > 3 else 4
cap = int(sys.argv[4]) if len(sys.argv) > 4 else 5_500_000

pat = re.compile(r'^core +0: (\d) (0x[0-9a-f]+) \((0x[0-9a-f]+)\)(?:\s+x(\d+)\s+(0x[0-9a-f]+))?')

def spike_commits():
    out = 0
    with open(log_f) as f:
        for l in f:
            m = pat.match(l)
            if m:
                pcv = int(m.group(2), 16)
                if pcv < MINPC:
                    continue
                rd = (int(m.group(4)) if m.group(4) is not None else 0)
                rv = (int(m.group(5), 16) if m.group(5) is not None else None)
                yield (pcv, int(m.group(3), 16), rd, rv)
                out += 1
                if out >= cap:
                    return

gen = spike_commits()
r = open(retire_f, 'rb')

MINPC = int(sys.argv[5], 16) if len(sys.argv) > 5 else 0x80400000   # compare only kernel-region retire streams

def retires():
    while True:
        d = r.read(32)
        if len(d) < 32:
            return
        v = struct.unpack('<8I', d)
        if v[1] >= MINPC:
            yield v

rg = retires()
first = next(rg)
# advance our stream to the first kernel-region record (head entry PA 0x804xxxxx
# or VA 0xXXXXxxx0 region the runner records unmasked)
while True:
    v = first
    pcv = v[1]
    if (0x80400000 <= pcv <= 0x80500000) or (pcv >= 0xc0000000):
        break
    try:
        first = next(rg)
    except StopIteration:
        print('no kernel-region record in our trace'); sys.exit(1)
cyc0, pc0, insn0 = first[0:3]
off = 0
found = False
sp = None
while True:
    try:
        sp = next(gen)
    except StopIteration:
        break
    if sp[0] == pc0 and sp[1] == insn0:
        found = True
        break
    off += 1
if not found:
    print('sync failed (spike log lacks our first retire)'); sys.exit(1)
print('spike sync offset:', off)
n = 0
reps = 0
cyc, pc, insn, rd, wv = cyc0, pc0, insn0, first[3], first[4]
stv = first[5]
while True:
    spc, sins, srd, srv = sp
    if spc != pc or sins != insn:
        reps += 1
        print('#%d n=%d' % (reps, n))
        print('  CPU   pc=%08x insn=%08x rd=%2d wv=%08x st=%d ea=%08x' % (pc, insn, rd, wv, stv, ea))
        print('  SPIKE pc=%08x insn=%08x' % (spc, sins))
        if reps >= maxrep: break
    elif srv is not None and srd == rd and srv != wv:
        reps += 1
        print('#%d n=%d VALUE' % (reps, n))
        print('  CPU   pc=%08x insn=%08x x%d = %08x' % (pc, insn, rd, wv))
        print('  SPIKE pc=%08x insn=%08x x%d = %08x' % (spc, sins, srd, srv))
        if reps >= maxrep: break
    try:
        r2 = next(rg)
    except StopIteration:
        break
    try:
        sp = next(gen)
    except StopIteration:
        print('spike cap reached: compared %d retires' % n)
        break
    stv = r2[5]
    cyc, pc, insn, rd, wv, ea = r2[0], r2[1], r2[2], r2[3], r2[4], r2[6]
    n += 1
print('compared %d retires, %d divergences (sync offset %d)' % (n, reps, off))
