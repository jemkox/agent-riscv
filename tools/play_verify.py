import glob
import hashlib
import sys
import os
import re

# M11/D1: play_test must PROVE the keys had an effect. A no-key baseline run of
# the same binary for the same cycle budget is compared frame-by-frame against
# the scripted run: frames that finished rendering BEFORE the first scripted
# key press must be byte-identical, and at least one frame after that press
# must differ. The old "differs from frame 0" check passed even when the
# keyboard was dead (the attract demo changes frames by itself), and would
# PASS with keys doing nothing - this check cannot.


_hc = {}
def h(p):
    if p not in _hc:
        with open(p, 'rb') as f:
            _hc[p] = hashlib.md5(f.read()).hexdigest()
    return _hc[p]


def frame_cycles(logpath):
    cs = []
    with open(logpath) as f:
        for line in f:
            m = re.match(r'#frame=(\d+) cyc=(\d+)', line)
            if m:
                cs.append(int(m.group(2)))
    return cs


def first_press(script):
    # same grammar as tb/play_main.cpp: tcur starts at 2e6, '@N' advances,
    # a key token presses at tcur (first press cycle we need)
    if not script:
        return None
    tcur, pos = 2000000, 0
    while pos < len(script):
        c = script.find(',', pos)
        tok = script[pos:c] if c != -1 else script[pos:]
        pos = c + 1 if c != -1 else len(script)
        if not tok:
            continue
        if tok[0] == '@':
            tcur += int(tok[1:])
            continue
        name = tok.split(':')[0]
        if name and (len(name) == 1 or name in ('enter', 'esc', 'up', 'down',
                                                'left', 'right', 'fire', 'use')):
            return tcur
    return None


fs = sorted(glob.glob('build/play/frames/frame_*.ppm'))
fb = sorted(glob.glob('build/play_baseline/frames/frame_*.ppm'))
print('frames:', len(fs), 'baseline:', len(fb))
if len(fs) < 4 or len(fb) < 4:
    print('PLAY TEST FAIL: too few frames')
    sys.exit(1)

cs = frame_cycles('build/play/logs/run.out')
cb = frame_cycles('build/play_baseline/logs/run.out')

key = first_press(os.environ.get('PLAY_SCRIPT'))
if key is None:
    print('PLAY TEST FAIL: no scripted key in PLAY_SCRIPT')
    sys.exit(1)

n = min(len(fs), len(fb))
viol = 0
for i in range(n):
    if cs[i] < key:
        # frames rendered before the first key: states are identical, so
        # cycles and pixels must match exactly
        if cb[i] != cs[i] or h(fs[i]) != h(fb[i]):
            viol += 1
if viol:
    print(f'PLAY TEST FAIL: {viol} frames differ BEFORE the first key @cycle {key} (nondeterministic or wrong baseline)')
    sys.exit(1)
# first scripted frame that can already SEE the key (rendered after the press)
firstd = None
n_after = n_diff = 0
for i in range(n):
    if cs[i] > key:
        n_after += 1
        if h(fs[i]) != h(fb[i]):
            n_diff += 1
            if firstd is None:
                firstd = (i, cs[i])
print(f'frames common: {n} (run {len(fs)} vs baseline {len(fb)} - counts may diverge after keys change Doom)')
if firstd is None:
    print(f'PLAY TEST FAIL: keys have NO effect - all {n_after} frames after first key @{key} identical to no-key baseline')
    sys.exit(1)
print(f'PLAY TEST PASS: {len(fs)} frames, {n_diff}/{n_after} differ after first key @cycle {key}, first-diff=frame_{firstd[0]:03d} (rendered at cycle {firstd[1]})')
sys.exit(0)
