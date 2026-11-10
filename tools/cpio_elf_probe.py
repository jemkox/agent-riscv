#!/usr/bin/env python3
import sys
# cpio_elf_probe.py rootfs.cpio /init /bin/sh ...

def parse(data):
    i=0; out=[]
    while True:
        if data[i:i+6] not in (b'070701', b'070702', b'070707'):
            raise SystemExit('not newc cpio')
        size=int(data[i+54:i+62],16)
        namesize=int(data[i+94:i+102],16)
        name=data[i+110:i+110+namesize-1].decode('ascii','replace')
        h=i+110+namesize
        body=h+((-h)%4)
        end=body+size+((-size)%4)
        mode=int(data[i+6:i+14],16)
        out.append((name,mode,size,data[body:body+size]))
        if name == 'TRAILER!!!':
            return out
        i=end

names=set(sys.argv[2:])
entries=parse(open(sys.argv[1], 'rb').read())
for name,mode,filesz,data in entries:
    if name in names:
        print(name, oct(mode), filesz)
        if data[:4] == b'\x7fELF':
            print('elf:', ' '.join('%02x'%x for x in data[:52]))
            print('machine:%04x entry:%08x phoff:%08x shoff:%08x phnum:%04x' % (int.from_bytes(data[18:20],'little'), int.from_bytes(data[24:28],'little'), int.from_bytes(data[28:32],'little'), int.from_bytes(data[32:36],'little'), int.from_bytes(data[44:46],'little')))
            ph=int.from_bytes(data[28:32],'little')
            for j in range(int.from_bytes(data[44:46],'little')):
                off=ph+j*32
                ptype=int.from_bytes(data[off:off+4],'little'); poff=int.from_bytes(data[off+4:off+8],'little'); pv=int.from_bytes(data[off+8:off+12],'little')
                pfsz=int.from_bytes(data[off+16:off+20],'little'); pmsz=int.from_bytes(data[off+20:off+24],'little')
                flags=int.from_bytes(data[off+24:off+28],'little')
                print(f"ph{j}: ptype={ptype:08x} off={poff:08x} vaddr={pv:08x} fsz={pfsz:08x} memsz={pmsz:08x} flags={flags:08x}")
