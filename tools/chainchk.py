#!/usr/bin/env python3
# Check kernel trap-handler sp-chain invariant using the extended retire log.
# Head entries (old mscratch = 0) save/load the current sp through 8(tp).
import sys, struct
path = sys.argv[1]
VEC = 0x80473db4
HND_LD = 0x80473dc8
regs = [0] * 32
recs = 0
head = 0
nested = 0
viol = []
prev_pc = 0
pending = None

def is_sw(insn):
    return (insn & 0x7f) == 0x23 and ((insn >> 12) & 7) == 2

f = open(path, 'rb')
while True:
    b = f.read(32)
    if len(b) < 32:
        break
    cyc, pc, insn, rd, wv, st, ea, sd = struct.unpack('<8I', b)
    recs += 1
    if pc == VEC:
        # csrrw tp,mscratch,tp retires with rd=tp, wv=old mscratch.
        # Capture outer sp before applying this record's writeback.
        if rd == 4:
            if wv == 0:
                head += 1
                pending = (cyc, prev_pc, regs[2])
            else:
                nested += 1
                pending = None
    elif pc == HND_LD and pending is not None:
        # lw sp,8(tp): for head entries this must equal the trapped sp.
        _, mepc, sp_expected = pending
        if wv != sp_expected:
            viol.append((recs, cyc, mepc, sp_expected, wv, ea))
            if len(viol) >= 80:
                break
        pending = None
    if rd != 0:
        regs[rd] = wv
    prev_pc = pc

print('recs=%d head=%d nested=%d viol=%d' % (recs, head, nested, len(viol)))
for r, cyc, mepc, sp, loaded, ea in viol:
    print('MISMATCH rec=%d cyc=%d mepc=%08x expected_sp=%08x loaded_chain=%08x load_ea=%08x' % (r, cyc, mepc, sp, loaded, ea))
