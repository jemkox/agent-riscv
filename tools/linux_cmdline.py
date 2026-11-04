#!/usr/bin/env python3
import sys
# Patch a raw Linux binary's empty boot_command_line buffer in place.
# args: in.bin out.bin [cmdline] [addr]
def main():
    if len(sys.argv) < 3:
        print("usage: linux_cmdline.py <in.bin> <out.bin> [cmdline] [vma_addr]")
        return 1
    with open(sys.argv[1], "rb") as f:
        data = bytearray(f.read())
    cmdline = sys.argv[3] if len(sys.argv) > 3 else "console=ttyS0 earlycon=ns16550,serial"
    addr = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x8049b258
    base = 0x80000000
    off = addr - base
    if off < 0 or off >= len(data):
        print("patch offset outside file", off)
        return 1
    blob = cmdline.encode("ascii") + b"\0"
    if off + len(blob) > len(data):
        print("not enough room at patch offset")
        return 1
    data[off:off + len(blob)] = blob
    with open(sys.argv[2], "wb") as f:
        f.write(data)
    print("patched cmdline at %x" % addr)
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
