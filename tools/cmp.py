#!/usr/bin/env python3
# cmp.py LOGA LOGB -- differential compare of retire logs (lines starting with
# '#' are metadata and ignored). Prints TEST PASSED or TEST FAILED: <n> errors.
import sys, re
PAT = re.compile(
    r'^[0-9a-f]{8} [0-9a-f]{8} +\d+ [0-9a-f]{8}'
    r' [01] [0-9a-f]{8} [0-9a-f]{8} [0-9a-f]$'
)
def read(f):
    out = []
    for ln in open(f):
        ln = ln.strip()
        if ln and not ln.startswith('#') and PAT.match(ln): out.append(ln)
    return out
a = read(sys.argv[1]); b = read(sys.argv[2])
n = max(len(a), len(b)); errs = 0; first = None
for i in range(n):
    x = a[i] if i < len(a) else '<missing>'
    y = b[i] if i < len(b) else '<extra>'
    if x != y:
        errs += 1
        if first is None: first = (i, x, y)
if errs == 0:
    print("TEST PASSED (%d instrs)" % len(a))
    sys.exit(0)
print("TEST FAILED: %d errors" % errs)
if first:
    print("first diff at %d: rtl=%s iss=%s" % first)
sys.exit(1)
