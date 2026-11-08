#!/usr/bin/env python3
# mmu_pin_check.py IMG FW ROOTFS EXPECTED3   -- sha256-pin the L7 Buildroot build.
# EXPECTED3 = comma-separated sha256 of (Image, fw_dynamic.elf, rootfs_canon.cpio).
# On drift the build REGENERATED differently: fail with the actual values so the
# Makefile pin can be bumped intentionally (reproducibility gate for L7/L8).
import hashlib, sys
files = sys.argv[1:4]
exp = sys.argv[4].split(',')
got = []
for f in files:
    h = hashlib.sha256()
    with open(f, 'rb') as fh:
        for blk in iter(lambda: fh.read(1 << 20), b''):
            h.update(blk)
    got.append(h.hexdigest())
if got == exp:
    print('MMU PINS OK (kernel/fw/rootfs shas match: %s)' % ' '.join(x[:8] for x in got))
    sys.exit(0)
print('MMU PINS DRIFT: buildroot rebuild produced different binaries.')
for g, e in zip(got, exp):
    print('  got %s  expected %s' % (g, e[:12]))
print('If this change was intentional, bump MMU_KERNEL_SHA256/MMU_FW_SHA256/' \
      'MMU_ROOTFS_CANON_SHA256 to the got-values and note the config change in PROGRESS.md.')
sys.exit(1)
