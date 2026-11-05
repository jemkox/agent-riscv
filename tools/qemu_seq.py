#!/usr/bin/env python3
# Reconstruct the QEMU executed pc sequence from an in_asm,cpu trace log and
# compare it against the CPU retire record stream (build/linux/cpu_retire.bin).
# Trace format: blocks appear once ("IN:" + disas lines at first execution);
# every block execution is preceded by a cpu state dump with a " pc <hex>" line.
import sys, struct
trace_path, retire_path = sys.argv[1], sys.argv[2]
maxn = int(sys.argv[3]) if len(sys.argv) > 3 else 10**9

blocks = {}          # start pc -> list of (pc, insn) from first IN dump
cur_block = None
in_asm = False
exec_pcs = []        # sequence of block-start pcs in execution order
seen_dump = False
with open(trace_path) as f:
    for line in f:
        if line.startswith('IN:'):
            in_asm = True
            cur_block = None
            continue
        if in_asm:
            if line.startswith('Priv'):
                continue
            if line.startswith('0x'):
                try:
                    pc0 = int(line.split(':')[0], 16)
                except ValueError:
                    in_asm = False
                    continue
                rest = line.split(':', 1)[1].strip()
                word = rest.split()[0] if rest else ''
                try:
                    insn = int(word, 16)
                except ValueError:
                    insn = None
                if insn is None:
                    in_asm = False
                    continue
                if cur_block is None:
                    cur_block = (pc0, [])
                    blocks[pc0] = cur_block[1]
                cur_block[1].append((pc0, insn))
                continue
            in_asm = False
            continue
        if line.startswith(' pc '):
            p = line.split()
            if len(p) >= 2:
                try:
                    exec_pcs.append(int(p[1], 16))
                except ValueError:
                    pass

# Expand to per-instruction executed sequence.
seq = []
missing = 0
for pc in exec_pcs:
    b = blocks.get(pc)
    if b is None:
        missing += 1
        continue
    seq.extend(b)
    if len(seq) >= maxn:
        break

print('blocks=%d exec_pcs=%d expanded=%d missing=%d' % (len(blocks), len(exec_pcs), len(seq), missing))

# Align: QEMU trace may begin with a stub; find first kernel-entry pc.
k0 = 0
while k0 < len(seq) and seq[k0][0] != 0x80000000:
    k0 += 1
print('kernel entry at seq index %d' % k0)
seq = seq[k0:]

# CPU retire stream
start_pc = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x80000000
skipped = 0
while True:
    b = f.read(32)
    if len(b) < 32:
        break
    cyc, pc, insn = struct.unpack('<8I', b)[:3]
    if pc == start_pc:
        break
    skipped += 1
print('skipped=%d until start_pc=%08x' % (skipped, start_pc))

i = 0
mism = 0
for i in range(1, min(len(seq), maxn) + 1):
    qpc, qinsn = seq[i - 1]
    if pc != qpc:
        mism += 1
        if mism <= 6:
            print('MISMATCH n=%d cpu=%08x q=%08x' % (i, pc, qpc))
        break
    if insn is not None and qinsn is not None and insn != qinsn:
        mism += 1
        if mism <= 6:
            print('INSN MISMATCH n=%d cpu=%08x q=%08x' % (i, pc, qinsn))
        break
    b = f.read(32)
    if len(b) < 32:
        break
    cyc, pc, insn = struct.unpack('<8I', b)[:3]
print('compared=%d mismatches=%d' % (i, mism))
