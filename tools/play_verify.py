import glob
import hashlib
import sys

fs = sorted(glob.glob('build/play/frames/frame_*.ppm'))
print('frames:', len(fs))
if len(fs) < 4:
    print('PLAY TEST FAIL: too few frames')
    sys.exit(0)


def h(p):
    with open(p, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()


h0 = h(fs[0])
first = None
changed = 0
for p in fs[1:]:
    if h(p) != h0:
        changed += 1
        if first is None:
            first = p
if first:
    print(f'PLAY TEST PASS: {len(fs)} frames, {changed} differ from frame 0, first-diff={first}')
else:
    print('PLAY TEST FAIL: all saved frames identical (no input-driven change)')
