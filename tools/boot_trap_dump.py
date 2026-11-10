#!/usr/bin/env python3
# Scan a CPU retire trace and dump the last trap-entry boundaries with context.
# usage: boot_trap_dump.py TRACE [N_TRAPS] [AFTER]
import struct, sys, collections

trace_path = sys.argv[1]
ntraps = int(sys.argv[2]) if len(sys.argv) > 2 else 12
after = int(sys.argv[3]) if len(sys.argv) > 3 else 30

def decode_next(pc, insn):
    op = insn & 0x7f
    if op == 0x6f:
        off = (((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xff) << 12) | (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3ff) << 1)
        off = (off ^ 0x100000) - 0x100000 if (off >> 20) & 1 else off
        return (pc + off) & 0xffffffff
    if op == 0x67:
        return None
    if op == 0x63:
        return None
    return (pc + 4) & 0xffffffff

traps = []
prev = None
ring = collections.deque()
after_count = 0
after_records = []
pending = None
with open(trace_path, "rb") as f:
    n = 0
    while True:
        rec = f.read(32)
        if len(rec) < 32:
            break
        n += 1
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", rec)
        rec = (n, cyc, pc, insn, rd, wv, st, ea, sd)
        if pending:
            after_records.append(rec)
            after_count += 1
            if after_count >= after:
                pending[8] = after_records
                traps.append(tuple(pending))
                pending = None
                after_count = 0
                after_records = []
        if prev:
            pn, ppc, pinsn = prev
            nxt = decode_next(ppc, pinsn)
            if nxt is not None and pc != nxt:
                pending = [len(traps) + 1, n, pn, ppc, pinsn, pc, insn, list(ring), []]
                after_count = 0
                after_records = []
        ring.append(rec)
        if len(ring) > after + 5:
            ring.popleft()
        prev = (n, pc, insn)

if pending:
    pending[8] = after_records
    traps.append(tuple(pending))

for tr in traps[-ntraps:]:
    k, n, pn, ppc, pinsn, pc, insn, hist, aft = tr
    print(f"TRAP entry_n={n} prev_n={pn} prev_pc={ppc:08x} prev_insn={pinsn:08x} handler_pc={pc:08x}")
    print("before:")
    for r in hist[-10:]:
        n2, cyc2, pc2, insn2, rd2, wv2, st2, ea2, sd2 = r
        print(f"  n={n2} cyc={cyc2:08x} pc={pc2:08x} insn={insn2:08x} r{rd2}<={wv2:08x} st={st2} ea={ea2:08x} sd={sd2:08x}")
    print("after:")
    for r in aft[:after]:
        n2, cyc2, pc2, insn2, rd2, wv2, st2, ea2, sd2 = r
        print(f"  n={n2} cyc={cyc2:08x} pc={pc2:08x} insn={insn2:08x} r{rd2}<={wv2:08x} st={st2} ea={ea2:08x} sd={sd2:08x}")
