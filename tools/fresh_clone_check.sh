#!/bin/sh
# Fresh-clone reproducibility gate (run after committing, before saying a round is done):
# clone the committed HEAD into a scratch dir, seed the pinned external deps locally
# (deps/ is generated, not in git; the sandbox has no network) and rebuild the required
# suite list from scratch. Catches Makefile dir-rule/order-only breakage that the dirty
# main tree hides (e.g. $(B)/spike: had no rule -> pattern rule %.elf under it failed
# only in a clean clone). Extend the list as suites grow.
set -eu
SRC=/home/jemko/agent-workspace/hdl/rv32cpu
CLONE=/home/jemko/agent-workspace/tmp/fresh_rv32cpu
rm -rf "$CLONE"
git clone -q "file://$SRC" "$CLONE"
mkdir -p "$CLONE/deps"
# pinned deps the checked targets need; copy the local pinned copies (same pinned revs)
for d in riscv-tests riscv-arch-test coremark FreeRTOS-Kernel; do
  if [ -d "$SRC/deps/$d" ]; then cp -a "$SRC/deps/$d" "$CLONE/deps/$d"; fi
done
cd "$CLONE"
hdl make test
hdl make mmu
hdl make mmu5
hdl make spike_tests
hdl make fpga_full FPGA_FREQ=13 FPGA_SEED=4
echo "FRESH-CLONE CHECK PASSED"
