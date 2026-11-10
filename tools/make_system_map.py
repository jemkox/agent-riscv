#!/usr/bin/env python3
import subprocess, sys
cmd = [
    "hdl",
    "riscv64-unknown-elf-objdump",
    "-t",
    sys.argv[1],
]
out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
rows = []
for line in out.splitlines():
    p = line.split()
    if len(p) < 4:
        continue
    try:
        addr = int(p[0], 16)
    except Exception:
        continue
    if addr < 0xc0000000 or addr >= 0x100000000:
        continue
    typ = None
    for tok in p[1:]:
        if len(tok) == 1 and tok in "tTwWFf":
            typ = "T" if tok in "Ff" else tok
            break
    if typ is None:
        continue
    name = p[-1]
    rows.append((addr, typ, name))
rows.sort()
with open(sys.argv[2], 'w') as f:
    for a, t, n in rows:
        f.write(f"{a:08x} {t} {n}\n")
