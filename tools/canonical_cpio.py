#!/usr/bin/env python3
# Canonicalize a `newc` cpio archive so the BUILDROOT rootfs hash is reproducible.
# Buildroot regenerates rootfs.cpio with fresh mtimes and fresh fakeroot inode
# numbers (and nlink counters), so the raw sha changes on every build. We rewrite
# every header with: mtime fixed to 0, inode numbers remapped by first-appearance
# order, and nlink set to the entry count of that inode; mode/uid/gid/dev/
# filesize/name/payload stay verbatim. Entry order stays as Buildroot wrote it
# (its filelist is sorted). The result hashes are stable across rebuilds of the
# same file set; print the sha256 of the canonical stream to stderr.
#
# usage: python3 tools/canonical_cpio.py <in.cpio> <out.cpio>
import hashlib, sys

def pad4(n):
    return (4 - (n % 4)) % 4

def main(inp, outp):
    with open(inp, 'rb') as f:
        data = f.read()
    # pass A: parse records
    recs = []
    i = 0
    while i < len(data):
        if len(data) - i < 110:
            break
        hdr = data[i:i+110]
        if hdr[0:6] not in (b'070701', b'070702'):
            break
        fields = [hdr[6+t*8:14+t*8].decode() for t in range(13)]
        namesz = int(fields[11], 16)
        filesize = int(fields[6], 16)
        name_at = i + 110
        j = name_at + namesz + pad4(name_at + namesz)
        payload = data[j:j+filesize]
        recs.append((fields, data[name_at:name_at+namesz], payload))
        i = j + filesize + pad4(j + filesize)
        if data[name_at:name_at+10] == b'TRAILER!!!':
            break
    # inode remap by first appearance + per-inode entry counts
    ino_map = {}
    counts = {}
    for fields, _n, _p in recs:
        o = fields[0]
        if o not in ino_map:
            ino_map[o] = len(ino_map)
        counts[o] = counts.get(o, 0) + 1
    out = bytearray()
    for fields, name, payload in recs:
        f2 = list(fields)
        f2[0] = '%08X' % ino_map[fields[0]]   # ino (index 0)
        f2[4] = '%08X' % counts[fields[0]]    # nlink (index 4)
        f2[5] = '00000000'                    # mtime (index 5)
        newhdr = bytearray(b'070701')
        for v in f2:
            newhdr += v.encode()
        # pad name so (header + name) ends 4-byte aligned in the OUTPUT stream
        pos = len(out) + 110
        padn = pad4(pos + len(name))
        pos2 = pos + len(name) + padn
        padp = pad4(pos2 + len(payload))
        out += newhdr + name + b'\x00' * padn + payload + b'\x00' * padp
        if name[:10] == b'TRAILER!!!':
            break
    with open(outp, 'wb') as f:
        f.write(out)
    sys.stderr.write("sha256 %s  %s\n" % (hashlib.sha256(bytes(out)).hexdigest(), outp))

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__import__('os').path.basename(sys.argv[0]) + " <in.cpio> <out.cpio>")
    main(sys.argv[1], sys.argv[2])
