#!/usr/bin/env python3
"""Print raw spike commit-log lines around a parser instruction index.
usage: spike_idx.py <log> <index> [window]
"""
import sys, re
if len(sys.argv) < 3:
    print("usage: spike_idx.py <log> <index> [window]")
    sys.exit(2)
P = sys.argv[1]
IDX = int(sys.argv[2])
W = int(sys.argv[3]) if len(sys.argv) > 3 else 8
idx = 0
lines = []
with open(P, 'rb') as f:
    for line in f:
        if (line.startswith(b'core   0: 0x') or re.match(b'core   0: [0-9a-f] 0x', line)) and b'(' in line:
            commit = not line.startswith(b'core   0: 0x')
            if commit:
                if idx == IDX:
                    # print a window of commit lines and their preceding raw lines by storing ring
                    pass
                idx += 1
                if IDX-W <= idx-1 <= IDX+W:
                    lines.append((idx-1, line.decode(errors='replace').rstrip()))
            else:
                continue

print("target parser index:", IDX)
for i,l in lines:
    print("n=%d %s" % (i,l))
