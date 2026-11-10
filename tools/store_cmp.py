#!/usr/bin/env python3
"""Compare store/AMO data in Spike commit log vs RTL retire trace.
usage: store_cmp.py <spike_commits.log> <cpu_retire.bin> [max_n] [anchor_pc_hex]
Prints first few stream indexes where a store instruction's data differs.
"""
import sys, struct, re
if len(sys.argv) < 3:
    print("usage: store_cmp.py <spike_commits.log> <cpu_retire.bin> [max_n] [anchor_pc_hex]")
    sys.exit(2)
LOG, BIN = sys.argv[1], sys.argv[2]
MAXN = int(sys.argv[3]) if len(sys.argv) > 3 else 10**12
FIRST_RTL = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x80000000

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
                        idx += 1
                        continue
                    tail = line[o2+1:].decode(errors='replace')
                    mems = re.findall(r'\bmem\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)', tail)
                    yield (i, pc, ins, mems)
                i += 1

def rtl_iter(path):
    with open(path, 'rb') as f:
        rec = f.read(32)
        while len(rec) == 32:
            cyc, pc, ins, rd, wv, st, ea, sd = struct.unpack('<8I', rec)
            yield (pc, ins, rd, wv, st, ea, sd)
            rec = f.read(32)

def next_or_none(gen):
    try: return next(gen)
    except StopIteration: return None

def store_ins(ins):
    op = ins & 0x7f
    if op == 0x23:
        f3 = (ins >> 12) & 7
        return f3 in {0,1,2}
    if op == 0x2f:
        return True
    return False

it_s = spike_iter(LOG)
it_r = rtl_iter(BIN)
head = next_or_none(it_s)
while head is not None and head[1] != FIRST_RTL:
    head = next_or_none(it_s)
if head is None:
    print("spike stream exhausted before anchor; nothing to compare")
    sys.exit(2)

ns = 0
ring = []
mism = 0
srec = head
try:
    while True:
        rr = next_or_none(it_r)
        if srec is None or rr is None:
            break
        idx, spc, sins, mems = srec
        rpc, rins, rd, wv, st, ea, sd = rr
        ring.append((idx, spc, sins, mems, rpc, rins, rd, wv, st, ea, sd))
        bad_pc = spc != rpc or ((sins ^ rins) & 0xffffffff) != 0
        if store_ins(sins) and mems:
            sval = int(mems[-1][1], 16)
            if sval != sd:
                if mism == 0:
                    print("FIRST STORE-DATA MISMATCH at n=%d; context:" % idx)
                    for (i,pc,ins,mems,pc2,ins2,rd2,wv2,st2,ea2,sd2) in ring[-12:]:
                        tag = 'BAD' if (store_ins(ins) and mems and int(mems[-1][1],16) != sd2) else 'ok'
                        sstr = ('mem=%s val=%s' % (mems[-1][0],mems[-1][1])) if mems else 'mem=?'
                        print("n=%d spike pc=%08x insn=%08x %s | rtl pc=%08x insn=%08x ea=%08x sd=%08x %s" %
                              (i, pc, ins, sstr, pc2, ins2, ea2, sd2, tag))
                mism += 1
                if mism >= 8:
                    break
        ns += 1
        if ns >= MAXN: break
        if bad_pc:
            # ignore stream misalignment by falling back to pc/insn compare? For now just note
            pass
        srec = next_or_none(it_s)
except StopIteration:
    pass
print("compared %d instructions; store-data mismatches: %d" % (ns, mism))
sys.exit(0 if mism == 0 else 1)
