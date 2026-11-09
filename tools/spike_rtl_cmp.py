#!/usr/bin/env python3
"""Stream-compare the pinned spike commit log (golden retire PC/insn) against the
RTL retire .bin (from run_openboot, '<8I' records: cyc,pc,insn,rdf,wv,st,ea,sd).
Finds the FIRST divergence in the retired instruction stream (pc + raw insn).
usage: spike_rtl_cmp.py <spike_commits.log> <cpu_retire.bin> [max_n] [anchor_pc_hex]
Exits 0 only if streams are exhausted with zero mismatches within max_n.
"""
import sys, struct, collections

LOG, BIN = sys.argv[1], sys.argv[2]
MAXN = int(sys.argv[3]) if len(sys.argv) > 3 else 10**12
FIRST_RTL = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x80000000

def spike_iter(path):
    """yield (idx, pc, insn) per retired instruction from spike commit log."""
    i = 0
    with open(path, 'rb') as f:
        for line in f:
            if line.startswith(b'core   0: 0x') and b'(' in line:
                try:
                    a = line.index(b'0x') + 2
                    b2 = line.index(b' ', a)
                    pc = int(line[a:b2], 16)
                    o1 = line.index(b'(', b2)
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

def next_or_none(gen):
    try:
        return next(gen)
    except StopIteration:
        return None

head_rec = next_or_none(it_s)
while head_rec is not None and head_rec[1] != FIRST_RTL:
    head_rec = next_or_none(it_s)
if head_rec is None:
    print("spike stream exhausted before anchor 0x%08x; nothing to compare" % FIRST_RTL)
    sys.exit(2)

ns = 0
RING = collections.deque(maxlen=24)
mism = 0
stream = [head_rec]
try:
    while True:
        srec = stream[0] if stream else next_or_none(it_s)
        rr = next_or_none(it_r)
        if srec is None or rr is None:
            print("compared %d instrs; one stream exhausted (spike=%s rtl=%s)" %
                  (ns, srec is not None, rr is not None))
            break
        idx, spc, sins = srec
        if stream: stream.pop()
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
        ns += 1
        if ns >= MAXN: break
except StopIteration:
    pass
print("compared %d instructions; mismatches: %d" % (ns, mism))
sys.exit(0 if mism == 0 else 1)
