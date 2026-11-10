#!/usr/bin/env python3
# tools/kernel_filter_initramfs.py <in-kernel> <out-kernel> [entry...]
# Finds the embedded cpio gzip in a Linux kernel image and replaces it in-place
# while preserving the kernel file size. Default entry removed: etc/init.d/S40network.
import sys, gzip, zlib
import pathlib

def parse_cpio(data):
    i=0; entries=[]; names=[]
    while True:
        magic=data[i:i+6]
        if magic not in (b"070701", b"070702", b"070707"):
            raise SystemExit("not newc cpio")
        size=int(data[i+54:i+62],16)
        nsize=int(data[i+94:i+102],16)
        name=data[i+110:i+110+nsize-1].decode("ascii","replace")
        h=i+110+nsize
        body=h + ((-h) % 4)
        end=body + size + ((-size)%4)
        entries.append((name, bytearray(data[i:end])))
        names.append(name)
        if name == "TRAILER!!!":
            return entries,names
        i=end

def filter_cpio(entries, names, drop):
    out=bytearray()
    for name, block in entries:
        if name in drop:
            continue
        b=block
        if name in {x.rsplit("/",1)[0] if "/" in x else "." for x in names}:
            n=int(b[38:46].decode("ascii"),16)
            if n:
                b[38:46]=("%08x" % (n-1)).encode("ascii")
        out += b
    return out

def find_gzip(b):
    for off, x in enumerate(b):
        if x==0x1f and b[off+1:off+3]==b"\x8b\x08":
            try:
                o=zlib.decompressobj(-15)
                data=o.decompress(b[off+10:])
                unused=o.unused_data
                if len(unused)<8: continue
                if not data.startswith(b"070701"): continue
                end=off+10+(len(b)-off-10-len(unused))+8
                return off,end,data
            except Exception:
                pass
    return None

if len(sys.argv)<3:
    raise SystemExit("usage: tools/kernel_filter_initramfs.py in-kernel out-kernel [entry...]")
in_path=pathlib.Path(sys.argv[1]); out_path=pathlib.Path(sys.argv[2])
drop=set(sys.argv[3:]) or {"etc/init.d/S40network"}
b=bytearray(in_path.read_bytes())
found=find_gzip(b)
if not found:
    raise SystemExit("embedded initramfs not found")
off,end,data=found
entries,names=parse_cpio(data)
filtered=filter_cpio(entries,names,drop)
new_gz=gzip.compress(bytes(filtered), mtime=0)
# Preserve original file length. Write the replacement at the same offset, then
# pad with zeros from the new gzip end to the old end.
b[off:end]=new_gz + b"\0" * max(0, (end-off)-len(new_gz))
out_path.write_bytes(bytes(b))
print(f"patched at off={off} old_len={end-off} new_gz_len={len(new_gz)} old_init_len={len(data)} new_init_len={len(filtered)}")
