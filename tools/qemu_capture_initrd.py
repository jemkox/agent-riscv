#!/usr/bin/env python3
import subprocess, sys
kernel, dtb, initrd, out_txt, trace_txt = sys.argv[1:6]
timeout = float(sys.argv[6]) if len(sys.argv) > 6 else 30.0
cmd = [
    'qemu-system-riscv32',
    '-machine', 'virt', '-m', '64M', '-bios', 'none',
    '-kernel', kernel, '-dtb', dtb, '-initrd', initrd,
    '-append', 'console=ttyS0 earlycon=ns16550,mmio,0x10000000 initramfs_async=0',
    '-d', 'cpu,in_asm,int', '-D', trace_txt, '-nographic',
]
with open(out_txt, 'w') as f:
    p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.DEVNULL)
    try:
        p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.terminate()
