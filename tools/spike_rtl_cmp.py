#!/usr/bin/env python3
"""Stream-compare the pinned spike commit log (golden retire PC/insn) against the
RTL retire .bin (from run_openboot, '<8I' records: cyc,pc,insn,rdf,wv,st,ea,sd).
Finds the FIRST divergence in the retired instruction stream (pc + raw insn).
usage: spike_rtl_cmp.py <spike_commits.log> <cpu_retire.bin> [max_n]
"""
import sys, struct, collections

LOG, BIN = sys.argv[1], sys.argv[2]
MAXN = int(sys.argv[3]) if len(sys.argv) > 3 else 10**12

def spike_iter(path):
    """yield (idx, pc, insn) per retired instruction from spike commit log."""
    i = 0
    with open(path, 'rb') as f:
        for line in f:
            if line.startswith(b'core   0: 0x') and b'(' in line:
                # "core   0: 0xPC (0xINSTR) disasm"
                try:
                    a = line.index(b'0x') + 2
                    b = line.index(b' ', a)
                    pc = int(line[a:b], 16)
                    o1 = line.index(b'(', b)
                    o2 = line.index(b')', o1)
                    ins = int(line[o1+1:o2], 16)
                except (ValueError, IndexError):
                    continue
                yield (i, pc, ins)
                i += 1

def rtl_iter(path):
    with open(path, 'rb') as f:
        rec = f.read(32)
        while len(rec) == 32:
            cyc, pc, ins, rdf, wv, st, ea, sd = struct.unpack('<8I', rec)
            yield pc, ins
            rec = f.read(32)

it_s = spike_iter(LOG)
it_r = rtl_iter(BIN)
FIRST_RTL = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x80000000
while True:
    head_rec = next(it_s)
    if head_rec[1] == FIRST_RTL: break
_pending = head_rec
def _stream(it, first):
    yield first
    yield from it
import collections
ns = 0
RING = collections.deque(maxlen=24)
mism = 0
for (idx, spc, sins) in _stream(it_s, _pending):
    rr = next(it_r)
    rpc, rins = rr
    RING.append((idx, spc, sins, rpc, rins))
    if spc != rpc or ((sins ^ rins) & 0xffffffff) != 0:
        if mism == 0:
            print("FIRST DIVERGENCE at n=%d; context:" % idx)
            for r in RING:
                mark = "  OK " if (r[1]==r[3] and (r[2]^r[4])==0) else " BAD "
                print("n=%d spike pc=%08x insn=%08x | rtl pc=%08x insn=%08x %s" % (r[0],r[1],r[2],r[3],r[4],mark))
        mism += 1
        if mism >= 4: break
    if idx >= MAXN: break
print("compared", ns, "instructions; mismatches:", mism)
