#!/usr/bin/env python3
import struct, sys
path = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20000000
ops = {}
st_flags = {}
first_st1 = None
first_store_op = None
count = 0
with open(path, "rb") as f:
    for k in range(limit):
        b = f.read(32)
        if len(b) < 32:
            break
        cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack("<8I", b)
        op = insn & 0x7f
        ops[op] = ops.get(op, 0) + 1
        st_flags[st] = st_flags.get(st, 0) + 1
        if st and first_st1 is None:
            first_st1 = (k, cyc, pc, insn, st, ea, sd)
        if op == 0x23 and first_store_op is None:
            first_store_op = (k, cyc, pc, insn, rd, wv, st, ea, sd)
        count += 1
print(f"count {count}")
print("ops", ops)
print("st flags", st_flags)
if first_st1:
    k, cyc, pc, insn, st, ea, sd = first_st1
    print(f"first st1 rec {k} cyc {cyc} pc {pc:#x} insn {insn:08x} st {st} ea {ea:#x} sd {sd:08x}")
if first_store_op:
    k, cyc, pc, insn, rd, wv, st, ea, sd = first_store_op
    print(f"first op0x23 rec {k} cyc {cyc} pc {pc:#x} insn {insn:08x} st {st} ea {ea:#x} sd {sd:08x}")
