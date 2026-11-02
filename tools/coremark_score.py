#!/usr/bin/env python3
# coremark_score.py LOG -- checks a CoreMark run log and prints CoreMark/MHz.
# CoreMark/MHz = iterations / (timed cycles / 1e6); it does not depend on the
# CPU_HZ the port reports seconds with. Exits 1 unless CoreMark validated its CRCs.
import re
import sys

log = open(sys.argv[1]).read()
it = re.search(r'^Iterations\s*:\s*(\d+)', log, re.M)
ticks = re.search(r'^Total ticks\s*:\s*(\d+)', log, re.M)
ok = 'Correct operation validated' in log and 'ERROR' not in log
if not (it and ticks):
    print('COREMARK FAIL: no Iterations/Total ticks in log')
    sys.exit(1)
iters, cyc = int(it.group(1)), int(ticks.group(1))
print(f'CoreMark/MHz = {iters / (cyc / 1e6):.3f}  ({iters} iterations in {cyc} cycles, '
      f'{cyc / iters:.0f} cycles/iteration)')
if not ok:
    print('COREMARK FAIL: CRCs not validated (see log)')
    sys.exit(1)
print('COREMARK PASS: CRCs validated')
