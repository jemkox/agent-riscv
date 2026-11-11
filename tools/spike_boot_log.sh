#!/bin/sh
# Full Spike boot with per-commit log written OUTSIDE the hdl sandbox (spike is a
# reference tool, big log ok on ext4). The commit log (stderr) ends with the boot
# halt or the kill timeout; compare it against build-linux/mmu3/cpu_retire.bin.
OUT=$(pwd)/build/linux/logs
mkdir -p "$OUT"
rm -f "$OUT/spike_commits.log" "$OUT/spike_c.out"
( sleep 120; printf "root\n"; sleep 10; printf "uname -a\n"; sleep 10; printf "cat /proc/cpuinfo\n"; sleep 10; printf "poweroff\n"; sleep 10 ) |
BR=${BR_MMU_IMG:-../../build-linux/mmu3/images}
SPIKE=${SPIKE_BIN:-spike}
timeout 600 "$SPIKE" --isa=rv32ima_zicsr_zifencei_zicntr -m64 -l --log-commits \
  --kernel "$BR/Image" \
  --initrd "$BR/rootfs.cpio" \
  --bootargs "console=ttyS0 earlycon" \
  "$BR/fw_jump.elf" > "$OUT/spike_c.out" 2> "$OUT/spike_commits.log"
