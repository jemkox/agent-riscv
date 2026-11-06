#!/usr/bin/env python3
# tools/kernel_disable_embedded_initramfs.py <in-kernel> <out-kernel>
# Zeroes the 4-byte embedded-initramfs size field after the appended cpio gzip.
# The gzip bytes remain, but the kernel should then use the external initrd only.
import sys, zlib, struct, pathlib

def find_gzip(b):
    for off, x in enumerate(b):
        if x != 0x1f:
            continue
        if b[off+1:off+3] != b"\x8b\x08":
            continue
        try:
            o = zlib.decompressobj(-15)
            data = o.decompress(b[off+10:])
            unused = o.unused_data
            if len(unused) < 8 or not data.startswith(b"070701"):
                continue
            end = off + 10 + (len(b) - off - 10 - len(unused)) + 8
            return off, end
        except Exception:
            pass
    return None

if len(sys.argv) < 3:
    raise SystemExit("usage: tools/kernel_disable_embedded_initramfs.py in-kernel out-kernel")
in_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
b = bytearray(in_path.read_bytes())
found = find_gzip(b)
if not found:
    raise SystemExit("embedded initramfs not found")
off, end = found
old_len = struct.pack("<I", end - off)
p = b.find(old_len, end, end + 128)
if p < 0:
    raise SystemExit("embedded-initramfs size field not found")
b[p:p+4] = b"\x00\x00\x00\x00"
out_path.write_bytes(bytes(b))
print(f"zeroed embedded initramfs size at off={p}; old_len={end-off}")
