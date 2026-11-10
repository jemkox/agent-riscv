#!/bin/sh
# Full Spike boot with per-commit log written OUTSIDE the hdl sandbox (spike is a
# reference tool, big log ok on ext4). The commit log (stderr) ends with the boot
# halt or the kill timeout; compare it against build-linux/mmu3/cpu_retire.bin.
OUT=$(pwd)/build/linux/logs
mkdir -p "$OUT"
rm -f "$OUT/spike_commits.log" "$OUT/spike_c.out"
( sleep 120; printf "root\n"; sleep 10; printf "uname -a\n"; sleep 10; printf "cat /proc/cpuinfo\n"; sleep 10; printf "poweroff\n"; sleep 10 ) |
timeout 600 /home/jemko/.local/bin/spike --isa=rv32ima_zicsr_zifencei_zicntr -m64 -l --log-commits \
  --kernel ../../build-linux/mmu3/images/Image \
  --initrd ../../build-linux/mmu3/images/rootfs.cpio \
  --bootargs "console=ttyS0 earlycon" \
  ../../build-linux/mmu3/images/fw_jump.elf > "$OUT/spike_c.out" 2> "$OUT/spike_commits.log"
