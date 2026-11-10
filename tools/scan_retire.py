#!/usr/bin/env python3
import struct, sys
path = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 100
with open(path, "rb") as f:
    ops = {}
    st_flags = {}
    store_ops = []
    for k in range(n):
        b = f.read(32)
        if len(b) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", b)
        op = insn & 0x7f
        f3 = (insn >> 12) & 7
        ops[op] = ops.get(op, 0) + 1
        st_flags[st] = st_flags.get(st, 0) + 1
        if op == 0x23:
            store_ops.append((k, cyc, pc, insn, rd, wv, st, ea, sd))
print("op counts", ops)
print("st flags", st_flags)
print("first stores:", len(store_ops))
for r in store_ops[:5]:
    print("store", r[1], "pc", f"{r[2]:#x}", "insn", f"{r[3]:#08x}", "st", r[5], "ea", f"{r[6]:#x}", "sd", f"{r[7]:#x}")
