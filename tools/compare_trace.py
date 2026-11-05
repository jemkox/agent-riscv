#!/usr/bin/env python3
import sys
import struct
import itertools

HEXD = set('0123456789abcdef')

def cpu_records(path):
    with open(path, 'rb') as f:
        data = b''
        while True:
            chunk = f.read(12 * 8192)
            data += chunk
            n = (len(data) // 12) * 12
            if n:
                for rec in struct.iter_unpack('<III', data[:n]):
                    yield rec
                data = data[n:]
            if not chunk:
                break

def qemu_iter(path):
    n = 0
    with open(path, 'r', errors='replace') as f:
        for line in f:
            n += 1
            if not line.startswith('0x'):
                continue
            parts = line.split(':', 1)
            if len(parts) != 2:
                continue
            tok = parts[1].lstrip().split(' ', 1)[0]
            if len(tok) == 8 and all(c in HEXD for c in tok):
                yield n, int(parts[0][2:], 16), int(tok, 16)

def main():
    if len(sys.argv) < 3:
        print("usage: compare_trace.py <cpu_retire.bin> <qemu_trace.log> [limit]")
        return
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else None
    qgen = qemu_iter(sys.argv[2])
    if limit is not None:
        qgen = itertools.islice(qgen, limit)
    qgen = iter(qgen)
    cpu_gen = cpu_records(sys.argv[1])
    try:
        first_cyc, first_pc, first_insn = next(cpu_gen)
    except StopIteration:
        print("CPU empty")
        return
    q = 0
    while True:
        try:
            qline, qpc, qinsn = next(qgen)
        except StopIteration:
            print(f"QEMU ended before first CPU: cpu_pc={first_pc:08x} cpu_insn={first_insn:08x} q_total={q}")
            return
        q += 1
        if qpc == first_pc and qinsn == first_insn:
            break
    c = 1
    for cyc, pc, insn in itertools.chain([(first_cyc, first_pc, first_insn)], cpu_gen):
        if cyc == first_cyc:
            continue
        try:
            qline, qpc, qinsn = next(qgen)
        except StopIteration:
            print(f"QEMU ended first: matched={c-1} cpu_n={c} q_total={q}")
            return
        q += 1
        if pc != qpc or insn != qinsn:
            print(f"MISMATCH cpu_n={c} cpu_cyc={cyc} cpu_pc={pc:08x} cpu_insn={insn:08x} q_n={q} q_line={qline} q_pc={qpc:08x} q_insn={qinsn:08x}")
            return
        c += 1
    try:
        qline, qpc, qinsn = next(qgen)
        print(f"CPU ended first: matched={c-1} cpu_total={c-1} extra_q_line={qline} q_total={q+1} extra_q_pc={qpc:08x} extra_q_insn={qinsn:08x}")
    except StopIteration:
        print(f"EXACT CPU MATCH: matched={c-1} cpu_total={c-1} q_total={q}")

if __name__ == '__main__':
    main()
