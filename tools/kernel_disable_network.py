#!/usr/bin/env python3
# tools/kernel_disable_network.py <in-kernel> <out-kernel> [entry...]
# Finds the embedded cpio gzip in a Linux kernel image, rewrites the named entry's
# body as a no-op shell script, and keeps the initramfs cpio length unchanged.
import sys, gzip, zlib, struct
import pathlib

def find_cpio_gzip(b):
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
            return off, end, data
        except Exception:
            pass
    return None

def patch_cpio_body(data, names, target_entries):
    i = 0
    data = bytearray(data)
    patched = False
    while True:
        if data[i:i+6] not in (b"070701", b"070702", b"070707"):
            break
        size = int(data[i+54:i+62], 16)
        nsize = int(data[i+94:i+102], 16)
        name = data[i+110:i+110+nsize-1].decode("ascii", "replace")
        h = i + 110 + nsize
        body = h + ((-h) % 4)
        end = body + size + ((-size) % 4)
        if name in target_entries and size:
            script = b"#!/bin/sh\nexit 0\n"
            body_bytes = data[body:body+size]
            replacement = script + b" " * max(0, size - len(script))
            body_bytes[:]=replacement[:size]
            data[body:body+size] = body_bytes
            patched = True
        if name == "TRAILER!!!":
            return data, patched
        i = end
    return data, patched

if len(sys.argv) < 3:
    raise SystemExit("usage: tools/kernel_disable_network.py in-kernel out-kernel [entry...]")
in_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
targets = set(sys.argv[3:]) or {"etc/init.d/S40network"}
b = bytearray(in_path.read_bytes())
found = find_cpio_gzip(b)
if not found:
    raise SystemExit("embedded initramfs not found")
off, end, cpio = found
new_cpio, patched = patch_cpio_body(cpio, None, targets)
if not patched:
    raise SystemExit("target entry not found in embedded initramfs")
new_gz = gzip.compress(bytes(new_cpio), mtime=0)
b[off:end] = new_gz
# Update the stored embedded-initramfs length field if it still contains the old length.
old_len = struct.pack("<I", end - off)
new_len = struct.pack("<I", len(new_gz))
i = b.find(old_len)
if i >= 0:
    b[i:i+4] = new_len
    print("updated initramfs-size field")
out_path.write_bytes(bytes(b))
print(f"patched embedded init off={off} old_gz={end-off} new_gz={len(new_gz)} cpio={len(cpio)}")
