#!/usr/bin/env python3
import sys

def main(argv):
    if len(argv) != 3:
        print("usage: tools/linux_gate.py System.map linux/gate.txt")
        return 1
    names = [
        "start_kernel",
        "kernel_init",
        "kernel_init_freeable",
        "wait_for_initramfs",
        "run_init_process",
    ]
    found = {}
    for line in open(argv[1]):
        parts = line.split()
        if len(parts) >= 3:
            addr, typ, name = parts[:3]
            if name in names and name not in found:
                try:
                    found[name] = int(addr, 16)
                except ValueError:
                    pass
    missing = [n for n in names if n not in found]
    if missing:
        print("missing symbols:", " ".join(missing))
        return 1
    with open(argv[2], "w") as out:
        for n in names:
            out.write("%s %08x\n" % (n, found[n]))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
