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

import re
SYNC_CSRS = {0xc00, 0xc80, 0xc01, 0xc81, 0xc02, 0xc82}
LOAD_F3 = {0, 1, 2, 4, 5, 6}
STORE_F3 = {0, 1, 2, 3}
R_TYPE = {0x33, 0x3b}

def csr_sync(ins):
    return ((ins & 0x7f) == 0x73) and (((ins >> 20) & 0xfff) in SYNC_CSRS)

def is_load(ins):
    return ((ins & 0x7f) == 0x03) and (((ins >> 12) & 7) in LOAD_F3)

def is_store(ins):
    return ((ins & 0x7f) == 0x23) and (((ins >> 12) & 7) in STORE_F3)

def source_synced(ins, state):
    op = ins & 0x7f
    rs1 = (ins >> 15) & 31
    rs2 = (ins >> 20) & 31
    if rs1 == 0:
        r1 = False
    else:
        r1 = bool(state[rs1])
    r2 = False
    if op in R_TYPE and rs2 != 0:
        r2 = bool(state[rs2])
    return r1 or r2

def spike_iter(path):
    """yield (idx, pc, insn, rd, wv, sync) per retired instruction from spike commit log.
    `sync` marks values that descend from clock/counter CSRs or from memory written
    by those values; the comparator should not compare those destination values.
    """
    i = 0
    state = [False] * 32          # value came from time/cycle/instret or propagated from it
    mem_sync = {}                 # spike memory word whose value is time-derived
    with open(path, 'rb') as f:
        for line in f:
            if (line.startswith(b'core   0: 0x') or re.match(b'core   0: [0-9a-f] 0x', line)) and b'(' in line:
                commit = not line.startswith(b'core   0: 0x')
                if not commit:
                    continue   # use the commit line (priv-prefixed) which carries state changes
                try:
                    a = line.index(b'0x') + 2
                    b2 = line.index(b' ', a)
                    pc = int(line[a:b2], 16)
                    o1 = line.index(b'(', b2)
                    o2 = line.index(b')', o1)
                    ins = int(line[o1+1:o2], 16)
                except (ValueError, IndexError):
                    continue
                tail = line[o2+1:].decode(errors='replace')
                ws = re.findall(r'\bx(\d+)\s+0x([0-9a-fA-F]+)', tail)
                mems = re.findall(r'\bmem\s+0x([0-9a-f]+)(?:\s+0x([0-9a-f]+))?', tail)
                rd, wv = 0, 0
                if not ws:
                    rd, wv = 0, 0
                elif len(ws) == 1:
                    rd, wv = int(ws[0][0]), int(ws[0][1], 16)
                    if rd == 0:
                        rd = -1   # x0 write: nothing golden to compare
                else:
                    rd, wv = -1, 0

                load = is_load(ins)
                store = is_store(ins)
                ins_sync = csr_sync(ins)
                propagated = source_synced(ins, state)
                rd_f = (ins >> 7) & 31

                if store:
                    for mem in mems:
                        addr = int(mem[0], 16)
                        rs2 = (ins >> 20) & 31
                        mem_sync[addr] = (rs2 != 0 and state[rs2])
                elif load and rd_f != 0 and mems:
                    rs1 = (ins >> 15) & 31
                    addr = int(mems[0][0], 16)
                    state[rd_f] = ((rs1 != 0 and state[rs1]) or bool(mem_sync.get(addr, False)))
                elif ins_sync:
                    if rd_f != 0:
                        state[rd_f] = True
                elif rd_f != 0 and ws:
                    state[rd_f] = propagated

                sync = ins_sync or (load and rd_f != 0 and state[rd_f]) or (rd != -1 and rd != 0 and state[rd])
                yield (i, pc, ins, rd, wv, sync)
                i += 1

def rtl_iter(path):
    with open(path, 'rb') as f:
        rec = f.read(32)
        while len(rec) == 32:
            cyc, pc, ins, rdf, wv, st, ea, sd = struct.unpack('<8I', rec)
            yield pc, ins, rdf, wv
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
        idx, spc, sins, srd, swv, sync = srec
        if stream: stream.pop()
        rpc, rins, rdf, rwv = rr
        RING.append((idx, spc, sins, rpc, rins, srd, swv, rdf, rwv, sync))
        bad = spc != rpc or ((sins ^ rins) & 0xffffffff) != 0
        if not bad and not sync and srd > 0 and (rdf != srd or rwv != swv):
            bad = True
        if bad:
            if mism == 0:
                print("FIRST DIVERGENCE at n=%d; context:" % idx)
                for r in RING:
                    mark = "  OK " if (r[1]==r[3] and (r[2]^r[4])==0 and
                                       (r[9] or not (r[5] > 0 and (r[7]!=r[5] or r[8]!=r[6])))) else " BAD "
                    print("n=%d spike pc=%08x insn=%08x rd=%s wv=%08x | rtl pc=%08x insn=%08x rd=%08x wv=%08x %s"
                          % (r[0],r[1],r[2],('  -' if r[5]<0 else '%2d'%r[5]),r[6],r[3],r[4],r[7],r[8],mark))
            mism += 1
            if mism >= 4: break
        ns += 1
        if ns >= MAXN: break
except StopIteration:
    pass
print("compared %d instructions; mismatches: %d" % (ns, mism))
sys.exit(0 if mism == 0 else 1)
