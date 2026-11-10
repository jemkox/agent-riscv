#!/bin/sh
# Deeper pinned-regime spike MMU-boot commit log (same regime as linux_mmu_spike_log,
# no real-time-clint; cap 80M insns). Console goes to c.out, commits to stderr log.
cd "$(dirname "$0")/.." || exit 1
mkdir -p build/linux/logs
rm -f build/linux/logs/spike_deep_c.out build/linux/logs/spike_deep_commits.log
echo "run started" > build/linux/logs/spike_deep_status.txt
( sleep 120; printf 'root\n'; sleep 10; printf 'uname -a\n'; sleep 10; printf 'cat /proc/cpuinfo\n'; sleep 10; printf 'poweroff\n'; sleep 10 ) | \
timeout 700 spike --isa=rv32ima_zicsr_zifencei_zicntr -m64 --dtb=linux/linux_mmu.dtb --pmpregions=0 \
  --instructions=80000000 -l --log-commits \
  --kernel=../../build-linux/mmu3/images/Image \
  --initrd=../../build-linux/mmu3/images/rootfs.cpio \
  ../../build-linux/mmu3/images/fw_jump.elf \
  > build/linux/logs/spike_deep_c.out 2> build/linux/logs/spike_deep_commits.log
echo "spike_deep exited $?" >> build/linux/logs/spike_deep_status.txt
