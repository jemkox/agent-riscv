#!/usr/bin/env python3
# tools/rootfs_drop_network.py <in.cpio> <out.cpio> [name...]
# Removes named entries from a Buildroot newc cpio and keeps parent nlink sane.
import sys

def parse(data):
    i = 0
    entries = []
    while True:
        magic = data[i:i + 6]
        if magic not in (b"070701", b"070702", b"070707"):
            raise SystemExit("not newc cpio")
        size = int(data[i + 54:i + 62], 16)
        namesize = int(data[i + 94:i + 102], 16)
        name = data[i + 110:i + 110 + namesize - 1].decode("ascii", "replace")
        h = i + 110 + namesize
        body = h + ((-h) % 4)
        end = body + size + ((-size) % 4)
        entries.append((name, bytearray(data[i:end]), body - i))
        if name == "TRAILER!!!":
            return entries
        i = end

def rebuild(entries):
    parents = {x.rsplit("/", 1)[0] if "/" in x else "." for x in names}
    out = bytearray()
    for name, block, _body in entries:
        if name in names:
            continue
        b = block
        if name in parents:
            n = int(b[38:46].decode("ascii"), 16)
            if n:
                b[38:46] = ("%08x" % (n - 1)).encode("ascii")
        out += b
    return out

if len(sys.argv) < 3:
    raise SystemExit("usage: tools/rootfs_drop_network.py in.cpio out.cpio [name...]")
data = open(sys.argv[1], "rb").read()
entries = parse(data)
names = set(sys.argv[3:])
if not names:
    names = {"etc/init.d/S40network"}
open(sys.argv[2], "wb").write(rebuild(entries))
