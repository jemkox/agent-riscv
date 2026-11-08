# trace_replay_check.py: independent check of a CPU retire trace (build/linux/cpu_retire.bin from the LINUX_DEBUG
# run_linux runner). It replays every retired instruction on its own register/memory/CSR model and reports the first
# results the CPU got wrong (RESULT, LD-ADDR, ST-ADDR, ST-DATA, AMO-ADDR, PC). Values it cannot know (device reads,
# counters, never-written memory, SC success) are taken from the trace unchecked. 0 reports = the datapath computed
# everything right, so look at control state (privilege, traps, CSRs) instead. Written by Claude, 2026-11-05.
# usage: python3 trace_replay_check.py cpu_retire.bin vmlinux.bin dtb dtb_addr_hex [max_reports]
import struct, sys

M32 = 0xFFFFFFFF
def sx(v, b): v &= (1 << b) - 1; return v - (1 << b) if v >> (b - 1) else v
def s32(v): return sx(v, 32)

trace, kern, dtbf, dtb_addr = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4], 16)
max_rep = int(sys.argv[5]) if len(sys.argv) > 5 else 30
if len(sys.argv) >= 10 and all(x.isdigit() for x in sys.argv[-2:]):
    nmin, nmax = map(int, sys.argv[-2:]); extra = sys.argv[6:-2]
else:
    nmin, nmax = 0, 10**18; extra = sys.argv[6:]
mem = {}                                   # byte address -> value (known bytes only)
# argv[2] loads at 0x80000000 (kernel for L4; fw_jump.bin for the L7 OpenSBI boot).
# Extra optional pairs after max_rep: ADDR_HEX PATH... (e.g. 80400000 Image 82800000 rootfs.cpio)
# The DTB loads LAST: the runner loads fw/kernel/initrd first and the DTB over the
# kernel's .bss hole, so initial RAM at dtb_addr = DTB bytes, not kernel zeros.
loads = [(0x80000000, kern)]
for i in range(0, len(extra) - 1, 2):
    loads.append((int(extra[i], 16), extra[i + 1]))
loads.append((dtb_addr, dtbf))
for base, path in loads:
    for i, b in enumerate(open(path, "rb").read()):
        mem[base + i] = b
def rd_mem(a, n):
    bs = [mem.get((a + i) & M32) for i in range(n)]
    return None if None in bs else sum(b << (8 * i) for i, b in enumerate(bs))
def wr_mem(a, n, v):
    for i in range(n): mem[(a + i) & M32] = (v >> (8 * i)) & 0xFF

reg = [0] + [None] * 31                    # None: not known yet
csr = {}                                   # plain-storage CSRs we model
PLAIN = {0x340: "mscratch", 0x305: "mtvec", 0x341: "mepc", 0x105: "stvec"}
reports = 0
stats = {"res": 0, "adopt": 0, "ld": 0, "st": 0, "traps": 0, "mret": 0}
def report(kind, n, cyc, pc, insn, msg):
    global reports
    reports += 1
    if nmin <= n <= nmax:
        print(f"#{reports} {kind} n={n} cyc={cyc} pc={pc:08x} insn={insn:08x}: {msg}", flush=True)
    if reports >= max_rep:
        print(stats); sys.exit(0)

prev = None                                # (n, cyc, pc, insn, expected next pc or None)
f = open(trace, "rb"); n = 0
while True:
    rec = f.read(32)
    if len(rec) < 32: break
    cyc, pc, insn, rdf, wv, st, ea, sd = struct.unpack("<8I", rec)
    n += 1
    # fetch: the word the CPU fetched must match its reported insn (RAM window only;
    # our ISA is uncompressed, so a misaligned pc still reads the 4-byte window).
    fw = rd_mem(pc, 4) if 0x80000000 <= pc < 0x84000000 else None
    if fw is not None and fw != insn:
        report("FETCH", n, cyc, pc, insn, f"insn {insn:08x}, memory has {fw:08x}")
    # control flow: was this the instruction the previous one should lead to?
    if prev and prev[4] is not None and pc != prev[4]:
        mt = csr.get(0x305)
        sc = csr.get(0x105)
        if (mt is not None and pc == (mt & ~3)) or (sc is not None and pc == (sc & ~3)):
            csr[0x341] = prev[4]; stats["traps"] += 1   # trap entry (M or S): mepc = the instruction that did not run
            if stats["traps"] <= 12:
                print(f"TRAP n={n} cyc={cyc} pc={pc:08x} mepc={csr[0x341]:08x} vec={(mt if mt is not None and pc==(mt&~3) else sc):08x} "
                      f"prev_insn={prev[3]:08x} (cause unknown: read handler's csrrs)")
        else:
            report("PC", n, cyc, pc, insn, f"expected next pc {prev[4]:08x} after {prev[2]:08x} ({prev[3]:08x})")
    op = insn & 0x7F; rd = (insn >> 7) & 31; f3 = (insn >> 12) & 7; r1 = (insn >> 15) & 31; r2 = (insn >> 20) & 31; f7 = insn >> 25
    a = reg[r1]; b = reg[r2]
    iimm = sx(insn >> 20, 12); simm = sx(((insn >> 25) << 5) | ((insn >> 7) & 31), 12)
    res = None; adopt = False; nxt = (pc + 4) & M32
    if op == 0x37: res = insn & 0xFFFFF000
    elif op == 0x17: res = (pc + (insn & 0xFFFFF000)) & M32
    elif op == 0x6F:
        off = sx(((insn >> 31) << 20) | (((insn >> 12) & 0xFF) << 12) | (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3FF) << 1), 21)
        res = (pc + 4) & M32; nxt = (pc + off) & M32
    elif op == 0x67:
        res = (pc + 4) & M32; nxt = ((a + iimm) & M32 & ~1) if a is not None else None
    elif op == 0x63:
        off = sx(((insn >> 31) << 12) | (((insn >> 7) & 1) << 11) | (((insn >> 25) & 0x3F) << 5) | (((insn >> 8) & 0xF) << 1), 13)
        if a is None or b is None: nxt = None
        else:
            t = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b), 6: a < b, 7: a >= b}[f3]
            nxt = (pc + off) & M32 if t else (pc + 4) & M32
    elif op == 0x03:                       # loads
        if a is not None:
            e = (a + iimm) & M32
            if e != ea: report("LD-ADDR", n, cyc, pc, insn, f"ea {ea:08x}, expected {e:08x}")
        size = {0: 1, 1: 2, 2: 4, 4: 1, 5: 2}[f3]
        v = rd_mem(ea, size)
        if v is None: adopt = True
        else: res = (sx(v, 8 * size) & M32) if f3 in (0, 1) else v; stats["ld"] += 1
    elif op == 0x23:                       # stores
        size = {0: 1, 1: 2, 2: 4}[f3]
        if a is not None:
            e = (a + simm) & M32
            if e != ea: report("ST-ADDR", n, cyc, pc, insn, f"ea {ea:08x}, expected {e:08x} (x{r1}={a:08x})")
        if b is not None:
            want = b & ((1 << (8 * size)) - 1)
            got = sd & ((1 << (8 * size)) - 1)
            lane = (sd >> (8 * (ea & 3))) & ((1 << (8 * size)) - 1)
            if got != want and lane != want:
                report("ST-DATA", n, cyc, pc, insn, f"data {sd:08x}, expected {want:0{2*size}x} (x{r2})")
            wr_mem(ea, size, want); stats["st"] += 1
        else:
            wr_mem(ea, size, sd if (sd >> (8 * size)) == 0 else (sd >> (8 * (ea & 3))))
    elif op == 0x13 or op == 0x33:
        if op == 0x13: y = iimm & M32; sh = (insn >> 20) & 31
        else: y = b; sh = (b & 31) if b is not None else None
        if a is None or y is None: adopt = True
        elif op == 0x33 and f7 == 1:      # M extension
            sa, sb = s32(a), s32(y)
            if f3 == 0: res = (a * y) & M32
            elif f3 == 1: res = ((sa * sb) >> 32) & M32
            elif f3 == 2: res = ((sa * y) >> 32) & M32
            elif f3 == 3: res = ((a * y) >> 32) & M32
            elif f3 == 4: res = M32 if y == 0 else (a if (sa == -2**31 and sb == -1) else int(sa / sb) & M32)
            elif f3 == 5: res = M32 if y == 0 else a // y
            elif f3 == 6: res = a if y == 0 else (0 if (sa == -2**31 and sb == -1) else (sa - sb * int(sa / sb)) & M32)
            elif f3 == 7: res = a if y == 0 else a % y
        else:
            alt = (f7 == 0x20)
            if f3 == 0: res = ((a - y) if (op == 0x33 and alt) else (a + y)) & M32
            elif f3 == 1: res = (a << sh) & M32
            elif f3 == 2: res = int(s32(a) < s32(y))
            elif f3 == 3: res = int(a < y)
            elif f3 == 4: res = a ^ y
            elif f3 == 5: res = (s32(a) >> sh) & M32 if alt else a >> sh
            elif f3 == 6: res = a | y
            elif f3 == 7: res = a & y
    elif op == 0x2F:                       # A extension
        f5 = insn >> 27
        if a is not None and a != ea: report("AMO-ADDR", n, cyc, pc, insn, f"ea {ea:08x}, expected {a:08x}")
        old = rd_mem(ea, 4)
        if f5 == 0x02:                     # lr.w
            if old is None: adopt = True
            else: res = old
        elif f5 == 0x03:                   # sc.w: trust the CPU's success flag, check the memory effect
            adopt = True
            if wv == 0 and b is not None: wr_mem(ea, 4, b)
        else:
            if old is None or b is None: adopt = True
            else:
                res = old
                nv = {0x00: (old + b) & M32, 0x01: b, 0x04: old ^ b, 0x0C: old & b, 0x08: old | b,
                      0x10: min(s32(old), s32(b)) & M32, 0x14: max(s32(old), s32(b)) & M32,
                      0x18: min(old, b), 0x1C: max(old, b)}.get(f5)
                if nv is not None: wr_mem(ea, 4, nv)
    elif op == 0x73:                       # SYSTEM: CSR ops, mret, wfi, ecall
        c = insn >> 20
        if f3 == 0:
            if insn == 0x30200073:         # mret
                nxt = csr.get(0x341); stats["mret"] += 1
            elif insn == 0x00000073: nxt = None
        else:
            old = csr.get(c)
            if c in PLAIN and old is not None: res = old
            else: adopt = True
            src = a if f3 < 4 else r1
            if src is not None and not (f3 in (2, 3, 6, 7) and r1 == 0):
                cur = old if old is not None else 0
                nv = {1: src, 2: cur | src, 3: cur & ~src & M32, 5: src, 6: cur | src, 7: cur & ~src & M32}[f3]
                if c in PLAIN and (old is not None or f3 in (1, 5)): csr[c] = nv & M32
                elif c in PLAIN: csr.pop(c, None)
    elif op == 0x0F: pass                  # fence
    else: adopt = True
    writes = op in (0x37, 0x17, 0x6F, 0x67, 0x03, 0x13, 0x33, 0x2F) or (op == 0x73 and f3 != 0)
    if writes and rd != 0:
        stats["res" if (res is not None and not adopt) else "adopt"] += 1
        if res is not None and not adopt and res != wv:
            report("RESULT", n, cyc, pc, insn, f"x{rd}={wv:08x}, expected {res:08x}"
                   + (f" (x{r1}={a:08x}" if a is not None else " (") + (f", x{r2}={b:08x})" if op in (0x33, 0x2F) and b is not None else ")"))
        reg[rd] = wv                       # follow the CPU after a report, so one bug is reported once
    prev = (n, cyc, pc, insn, nxt)
print(f"checked {n} instructions, {reports} reports", stats)
