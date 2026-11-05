#!/usr/bin/env python3
# Compare QEMU exec-trace (block entries) against CPU retire log, segment-wise.
# Trap vector entries are treated as segment boundaries; a side with an extra
# trap consumes its handler region before comparing continues.
import sys, struct

qlog, cbin, kbin = sys.argv[1], sys.argv[2], sys.argv[3]
VEC = 0x80473db4
REG_END = 0x80474030
kimg = open(kbin, 'rb').read()
KBASE = 0x80000000

def term(insn):
    op = insn & 0x7f
    f3 = (insn >> 12) & 7
    if op == 0x63: return True
    if op == 0x6f or op == 0x67: return True
    if op == 0x73 and f3 == 0: return True          # ecall/ebreak/xret
    return False

def decode(pc):
    off = pc - KBASE
    return kimg[off:off+4]

# QEMU block starts -> instruction pcs
qpcs = []
import re
pat = re.compile(r'\[([0-9a-f]{8})/([0-9a-f]{16})/')
starts = []
with open(qlog) as f:
    for line in f:
        m = pat.search(line)
        if m:
            starts.append(int(m.group(2), 16))

def qgen():
    for i, p in enumerate(starts):
        nxt = starts[i+1] if i+1 < len(starts) else None
        pc = p
        if p < KBASE or p >= KBASE + len(kimg):
            continue
        while True:
            b = decode(pc)
            if len(b) < 4: return
            insn = int.from_bytes(b, 'little')
            yield pc
            pc += 4
            if term(insn): break
            if nxt is not None and pc == nxt: break
            if nxt is not None and pc > nxt: break

cpu_iter = open(cbin, 'rb')

def cgen():
    while True:
        rec = cpu_iter.read(12)
        if len(rec) < 12: return
        cyc, pc, insn = struct.unpack('<III', rec)
        yield pc, cyc

qc, cc = qgen(), cgen()
try:
    q = next(qc)
    cp = next(cc)
except StopIteration:
    sys.exit(0)
while q != VEC:
    q = next(qc)
while cp[0] != VEC:
    cp = next(cc)

n = 0
mism = []
extra_q = extra_c = 0
while True:
    if q != cp[0]:
        if cp[0] == VEC or (VEC <= cp[0] < REG_END):
            while True:
                p = cp[0]
                if not (VEC <= p < REG_END) and p != VEC:
                    break
                try:
                    cp = next(cc)
                except StopIteration:
                    print('EXIT1 cpu-exhaust n=',n);sys.exit(0)
            extra_c += 1
            continue
        if q == VEC or (VEC <= q < REG_END):
            while True:
                p = q
                if not (VEC <= p < REG_END) and p != VEC:
                    break
                try:
                    q = next(qc)
                except StopIteration:
                    print('EXIT1 cpu-exhaust n=',n);sys.exit(0)
            extra_q += 1
            continue
        mism.append((n, q, cp[0], cp[1]))
        if len(mism) >= 8:
            break
    n += 1
    try:
        q = next(qc); cp = next(cc)
    except StopIteration:
        break
    if q == cp[0]:
        continue
    # try to resync: which side has an extra trap?
    if cp[0] == VEC or (VEC <= cp[0] < REG_END):
        while True:
            p = cp[0]
            if not (VEC <= p < REG_END) and p != VEC:
                break
            try:
                cp = next(cc)
            except StopIteration:
                print('EXIT1 cpu-exhaust n=',n);sys.exit(0)
        extra_c += 1
        continue
    if q == VEC or (VEC <= q < REG_END):
        while True:
            p = q
            if not (VEC <= p < REG_END) and p != VEC:
                break
            try:
                q = next(qc)
            except StopIteration:
                print('EXIT1 cpu-exhaust n=',n);sys.exit(0)
        extra_q += 1
        continue
    mism.append((n, q, cp[0], cp[1]))
    if len(mism) >= 8:
        break

print('compared=%d extra_q=%d extra_c=%d' % (n, extra_q, extra_c))
for t, qq, ccpc, cyc in mism:
    print('MISMATCH n=%d cyc=%d cpu=%08x qemu=%08x' % (t, cyc, ccpc, qq))
