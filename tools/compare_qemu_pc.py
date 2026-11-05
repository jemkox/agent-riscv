#!/usr/bin/env python3
import sys
import struct
import itertools

def cpu_iter(path):
    with open(path, 'rb') as f:
        data = b''
        while True:
            chunk = f.read(32 * 8192)
            data += chunk
            n = (len(data) // 32) * 32
            if n:
                for rec in struct.iter_unpack('<8I', data[:n]):
                    cyc, pc, insn, _rd, _wv, _st, _ea, _sd = rec
                    yield cyc, pc, insn
                data = data[n:]
            if not chunk:
                break

def qemu_pc_iter(path):
    with open(path, 'r', errors='replace') as f:
        for n, line in enumerate(f, 1):
            if line.startswith('Trace'):
                br = line.find('[')
                if br >= 0:
                    parts = line[br + 1:].split(']')[0].split('/')
                    if len(parts) >= 2 and len(parts[1]) >= 16:
                        pc = int(parts[1][-8:], 16)
                        yield n, pc
            elif line.startswith(' pc '):
                parts = line.split()
                if len(parts) == 2:
                    tok = parts[1]
                    if len(tok) == 8 and all(c in '0123456789abcdef' for c in tok):
                        yield n, int(tok, 16)

def main():
    if len(sys.argv) < 3:
        print("usage: compare_qemu_pc.py <cpu_retire.bin> <qemu_trace.log> [limit] [start_pc]")
        return
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else None
    start_pc = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0
    qgen = iter(qemu_pc_iter(sys.argv[2]))
    q = 0
    while True:
        try:
            qline, qpc = next(qgen)
        except StopIteration:
            print("QEMU ended before start_pc")
            return
        q += 1
        if qpc == start_pc:
            break
    cgen = cpu_iter(sys.argv[1])
    c = 1
    while True:
        try:
            first = next(cgen)
        except StopIteration:
            print("CPU empty")
            return
        if first[1] == start_pc:
            break
        c += 1
    qitems = itertools.chain([(qline, qpc)], qgen)
    compared = 0
    for cyc, pc, insn in itertools.chain([first], cgen):
        try:
            qline, qpc = next(qitems)
        except StopIteration:
            print(f"QEMU ended first: matched={compared} cpu_total={compared+1} q_total={q}")
            return
        q += 1
        if pc != qpc:
            print(f"MISMATCH cpu_n={c} cpu_cyc={cyc} cpu_pc={pc:08x} q_n={q} q_line={qline} q_pc={qpc:08x}")
            return
        compared += 1
        c += 1
        if limit is not None and compared >= limit:
            print(f"limit reached: compared={compared}")
            return
    print(f"CPU ended first: matched={compared} cpu_total={compared} q_total={q}")

if __name__ == '__main__':
    main()
