#!/usr/bin/env python3
"""Compare load destination values in Spike log vs RTL retire trace.
usage: load_cmp.py <spike_commits.log> <cpu_retire.bin> [max_n] [anchor_pc_hex]
"""
import sys, struct, re
if len(sys.argv) < 3:
    print("usage: load_cmp.py <spike_commits.log> <cpu_retire.bin> [max_n] [anchor_pc_hex]")
    sys.exit(2)
LOG, BIN = sys.argv[1], sys.argv[2]
MAXN = int(sys.argv[3]) if len(sys.argv) > 3 else 10**12
FIRST_RTL = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x80000000

LOAD_F3 = {0,1,2,4,5,6}
def is_load(ins):
    return (ins & 0x7f) == 0x03 and (((ins >> 12) & 7) in LOAD_F3)

def spike_iter(path):
    i = 0
    with open(path, 'rb') as f:
        for line in f:
            if (line.startswith(b'core   0: 0x') or re.match(b'core   0: [0-9a-f] 0x', line)) and b'(' in line:
                commit = not line.startswith(b'core   0: 0x')
                if commit:
                    try:
                        a = line.index(b'0x') + 2
                        b2 = line.index(b' ', a)
                        pc = int(line[a:b2], 16)
                        o1 = line.index(b'(', b2)
                        o2 = line.index(b')', o1)
                        ins = int(line[o1+1:o2], 16)
                    except (ValueError, IndexError):
                        i += 1
                        continue
                    tail = line[o2+1:].decode(errors='replace')
                    ws = re.findall(r'\bx(\d+)\s+0x([0-9a-fA-F]+)', tail)
                    rd, wv = 0, 0
                    if len(ws) == 1:
                        rd = int(ws[0][0]); wv = int(ws[0][1],16)
                        if rd == 0: rd = -1
                    elif len(ws) > 1:
                        rd, wv = -1, 0
                    yield (i, pc, ins, rd, wv, tail)
                i += 1

def rtl_iter(path):
    with open(path, 'rb') as f:
        rec = f.read(32)
        while len(rec) == 32:
            cyc, pc, ins, rd, wv, st, ea, sd = struct.unpack('<8I', rec)
            yield (pc, ins, rd, wv, ea)
            rec = f.read(32)

def nxt(g):
    try: return next(g)
    except StopIteration: return None

it_s = spike_iter(LOG)
it_r = rtl_iter(BIN)
head = nxt(it_s)
while head is not None and head[1] != FIRST_RTL:
    head = nxt(it_s)
if head is None:
    print("spike stream exhausted before anchor; nothing to compare")
    sys.exit(2)

ns = 0; ring = []; mism = 0
try:
    while True:
        rr = nxt(it_r)
        if head is None or rr is None: break
        idx, spc, sins, srd, swv, tail = head
        rpc, rins, rd, wv, ea = rr
        ring.append((idx,spc,sins,srd,swv,tail,rpc,rins,rd,wv,ea))
        if is_load(sins) and is_load(rins):
            if (rd != srd or wv != swv) and srd > 0:
                if mism == 0:
                    print("FIRST LOAD MISMATCH at n=%d; context:" % idx)
                    for i,spc2,sins2,srd2,swv2,tail2,rpc2,rins2,rd2,wv2,ea2 in ring[-12:]:
                        tag = 'BAD' if is_load(sins2) and is_load(rins2) and srd2 > 0 and (rd2 != srd2 or wv2 != swv2) else 'ok'
                        print("n=%d spike pc=%08x insn=%08x rd=%-2d wv=%08x %s | rtl pc=%08x insn=%08x rd=%08x wv=%08x ea=%08x %s" %
                              (i,spc2,sins2,srd2,swv2,tail2,rpc2,rins2,rd2,wv2,ea2,tag))
                mism += 1
                if mism >= 5:
                    break
        ns += 1
        if ns >= MAXN: break
        head = nxt(it_s)
except StopIteration:
    pass
print("compared %d instructions; load mismatches: %d" % (ns, mism))
sys.exit(0 if mism == 0 else 1)
