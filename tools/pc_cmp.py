#!/usr/bin/env python3
# PC/insn-only stream compare for boot debug: <spike_commits.log> <retire.bin> [max_n] [anchor_pc_hex]
import sys, struct, re
if len(sys.argv) < 3: sys.exit("usage: pc_cmp.py <spike_commits.log> <retire.bin> [max_n] [anchor]")
LOG, BIN = sys.argv[1], sys.argv[2]
MAXN = int(sys.argv[3]) if len(sys.argv) > 3 else 10**12
ANCHOR = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x80000000

def spike_pc(path):
    with open(path, 'rb') as f:
        for line in f:
            if not line.startswith(b'core   0:') or b'(' not in line: continue
            if line.startswith(b'core   0: 0x'): continue
            try:
                a = line.index(b'0x') + 2
                b = line.index(b' ', a)
                c = line.index(b'(', b)
                d = line.index(b')', c)
                yield int(line[a:b],16), int(line[c+1:d],16)
            except Exception:
                continue

def rtl_pc(path):
    with open(path, 'rb') as f:
        while True:
            rec = f.read(32)
            if len(rec) < 32: return
            _, pc, ins = struct.unpack('<8I', rec)[:3]
            yield pc, ins

it_s = spike_pc(LOG)
it_r = rtl_pc(BIN)
head = next(it_s, None)
while head and head[0] != ANCHOR: head = next(it_s, None)
if not head:
    print("spike stream exhausted before anchor 0x%08x" % ANCHOR); sys.exit(2)
ns = mism = 0
sp = head
try:
    for rp, ri in it_r:
        spc, sin = sp if ns == 0 else next(it_s)
        if spc != rp or sin != ri:
            mism += 1
            print("DIVERGE n=%d spike pc=%08x insn=%08x | rtl pc=%08x insn=%08x" % (ns, spc, sin, rp, ri))
            if mism >= 8: break
        ns += 1
        if ns >= MAXN: break
except StopIteration:
    print("compared %d instrs; mismatches: %d; spike or rtl exhausted" % (ns, mism)); sys.exit(1)
print("compared %d instrs; mismatches: %d" % (ns, mism)); sys.exit(0 if mism == 0 else 1)