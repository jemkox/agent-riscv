#!/usr/bin/env python3
# mmuself.py SFILE RTLLOG   (objdump -t of the test ELF on stdin)
# For each "# mmucheck <label> <expected-uint>" comment in the test source,
# the last write to a6 (x16) retired at or before <label>'s pc must equal
# expected. Finally gp (x27) must end at 1 and the log must show HALT=1.
import sys, re
src = open(sys.argv[1]).read()
log = open(sys.argv[2]).read()

labels = {}
for ln in sys.stdin:
    ln = ln.strip()
    p = ln.split()
    if len(p) >= 3 and re.fullmatch(r'[0-9a-fA-F]{1,16}', p[0]):
        # objdump -t formats: "ADDR T name" or "ADDR l .text 00000000 name"
        name = p[-1]
        if re.fullmatch(r'[A-Za-z_.][\w.$@]*', name) and not name.startswith('.L'):
            labels[name] = int(p[0], 16)

checks = re.findall(r'#\s*mmucheck\s+(\w+)\s+([0-9a-fA-Fx]+)', src)

rows = []
halt = False
for ln in log.splitlines():
    if ln.startswith('#SUMMARY'):
        halt = 'HALT=1' in ln
        continue
    f = ln.split()
    if len(f) == 8: rows.append((int(f[0], 16), int(f[2], 10), int(f[3], 16)))

ok = True
lo = 0
for lab, want in checks:
    want_v = int(want, 16)
    if lab not in labels:
        print("mmucheck label missing in ELF: %s" % lab); ok = False; continue
    pcs = labels[lab]
    last = None
    for (pc, rd, v) in rows:
        if pc <= pcs and rd == 16: last = v
    if last is None:
        print("no a6 write before %s" % lab); ok = False
    elif last != want_v:
        print("a6 before %s: got %d want %d" % (lab, last, want_v)); ok = False
gpl = [v for (pc, rd, v) in rows if rd == 3]   # gp = x3 (RV32 ABI)
if not gpl or gpl[-1] != 1:
    print("gp final: got %s want 1" % (gpl[-1] if gpl else None)); ok = False
if not halt:
    print("no HALT=1"); ok = False
print("MMUSELF PASSED" if ok else "MMUSELF FAILED")
sys.exit(0 if ok else 1)
