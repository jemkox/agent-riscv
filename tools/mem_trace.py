#!/usr/bin/env python3
"""Show recent memory accesses near a divergence index from Spike log and RTL trace.
usage: mem_trace.py <spike_commits.log> <cpu_retire.bin> <addr_lo> <addr_hi> <max_n> [last]
"""
import sys, struct, re
if len(sys.argv) < 6:
    print("usage: mem_trace.py <spike_commits.log> <cpu_retire.bin> <addr_lo> <addr_hi> <max_n> [last]")
    sys.exit(2)
LOG, BIN = sys.argv[1], sys.argv[2]
LO = int(sys.argv[3], 16); HI = int(sys.argv[4], 16); N = int(sys.argv[5]); LAST = int(sys.argv[6]) if len(sys.argv) > 6 else 50
LOAD_F3 = {0,1,2,4,5,6}; STORE_F3 = {0,1,2,3}

def load(ins):
    return (ins & 0x7f) == 0x03 and ((ins >> 12) & 7) in LOAD_F3
def store(ins):
    return (ins & 0x7f) == 0x23 and ((ins >> 12) & 7) in STORE_F3

out = []

idx = 0
with open(LOG, 'rb') as f:
    for line in f:
        if idx > N:
            break
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
                    idx += 1
                    continue
                tail = line[o2+1:].decode(errors='replace').strip()
                hits = []
                for m in re.finditer(r'\bmem\s+0x([0-9a-fA-F]+)(?:\s+0x([0-9a-fA-F]+))?', tail):
                    a = int(m.group(1), 16); v = int(m.group(2), 16) if m.group(2) else None
                    if LO <= a <= HI:
                        hits.append((a, v, m.start(), m.end()))
                if hits or (store(ins) or load(ins)):
                    # only keep lines with mem mentions in range, or any load/store line whose pc context
                    if hits:
                        out.append((idx, 'S', tail, pc, ins, hits))
            idx += 1

idx = 0
with open(BIN, 'rb') as f:
    rec = f.read(32)
    while len(rec) == 32 and idx <= N:
        cyc, pc, ins, rd, wv, st, ea, sd = struct.unpack('<8I', rec)
        if (LO <= ea <= HI) and (st == 1 or sd != 0 or load(ins)):
            out.append((idx, 'R', 'cyc=%08x pc=%08x ins=%08x st=%u ea=%08x sd=%08x rd=%08x wv=%08x' % (cyc,pc,ins,st,ea,sd,rd,wv), pc, ins, [(ea, sd if st else wv)]))
        idx += 1
        rec = f.read(32)

if LAST and len(out) > LAST:
    out = out[-LAST:]
for idx, typ, tail, pc, ins, hits in out:
    print('n=%d %s pc=%08x ins=%08x %s' % (idx, typ, pc, ins, tail))
