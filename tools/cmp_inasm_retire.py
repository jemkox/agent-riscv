import sys, struct, re

args = sys.argv[1:]
cpu, off, qlog, spc, limit = args[:5]
qstart = int(args[5]) if len(args) > 5 else 1
off = int(off); limit = int(limit); spc = int(spc, 16); qstart = int(qstart)

def qgen(path):
    rx = re.compile(r'^0x([0-9a-fA-F]{1,16}):(?:\s*([0-9a-fA-F]{1,8}))?')
    with open(path, errors='ignore') as f:
        for lineno, line in enumerate(f, 1):
            if lineno < qstart:
                continue
            m = rx.match(line)
            if m:
                insn = int(m.group(2), 16) if m.group(2) else 0
                yield int(m.group(1), 16), insn

def cpu_rec(path, off):
    with open(path, 'rb') as f:
        f.seek(off)
        while True:
            rec = f.read(32)
            if len(rec) < 32:
                break
            yield struct.unpack('<8I', rec[:32])

from itertools import chain
q = qgen(qlog)
found = False
for item in q:
    if item[0] == spc:
        found = True
        q = chain((item,), q)
        break
if not found:
    print('QEMU start PC not found')
    raise SystemExit(2)

recs = cpu_rec(cpu, off)
prev = []
for n in range(limit):
    try:
        r = next(recs)
    except StopIteration:
        print('CPU ended before', n)
        break
    while True:
        try:
            qp, qi = next(q)
        except StopIteration:
            print('QEMU ended before', n)
            raise SystemExit(2)
        if qi == 0x00000073 and pc != qp:
            print(f'skip qemu ecall pc={qp:08x}')
            continue
        break
    seq, pc, insn = r[0], r[1], r[2]
    if pc != qp:
        skipped = 0
        found = False
        for k in range(50000):
            try:
                r2 = next(recs)
            except StopIteration:
                break
            skipped += 1
            if r2[1] == qp:
                r = r2
                seq, pc, insn = r[0], r[1], r[2]
                found = True
                break
        if not found:
            print(f'FAIL real mismatch at n={n}: cpu_seq={seq} cpu_pc={pc:08x} insn={insn:08x} qemu_pc={qp:08x}')
            for pp in prev[-4:]:
                print(f'  prev cpu_pc={pp[1]:08x} qemu_pc={pp[0]:08x}')
            raise SystemExit(1)
        print(f'resynced cpu skip={skipped} to qemu_pc={qp:08x}')
    prev.append((qp, pc))
    if n < 8 or n % 50 == 0:
        print(f'match {n}: pc={pc:08x} seq={seq}')
else:
    print('COMPARE OK for', limit)
