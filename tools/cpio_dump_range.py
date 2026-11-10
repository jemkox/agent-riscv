#!/usr/bin/env python3
import sys
def parse(data):
    i=0; out=[]
    while True:
        if data[i:i+6] not in (b'070701',b'070702',b'070707'):
            raise SystemExit('not newc cpio')
        size=int(data[i+54:i+62],16)
        namesize=int(data[i+94:i+102],16)
        name=data[i+110:i+110+namesize-1].decode('ascii','replace')
        h=i+110+namesize
        body=h+((-h)%4)
        end=body+size+((-size)%4)
        out.append((name,data[body:body+size]))
        if name=='TRAILER!!!':
            return out
        i=end
cpio=sys.argv[1]; name=sys.argv[2]; off=int(sys.argv[3],0); ln=int(sys.argv[4],0)
for n,data in parse(open(cpio,'rb').read()):
    if n==name:
        b=data[off:off+ln]
        print(' '.join('%02x'%x for x in b))
        break
