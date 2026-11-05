#!/usr/bin/env python3
import sys, struct
path = sys.argv[1]
start_cyc = int(sys.argv[2], 0) if len(sys.argv)>2 else 0
end_cyc = int(sys.argv[3], 0) if len(sys.argv)>3 else 100000000
VEC = 0x80473db4
records=[]
f=open(path,'rb')
n=0
while True:
    b=f.read(32)
    if len(b)<32: break
    rec=struct.unpack('<8I',b); n+=1
    cyc, pc, insn, rd, wv, st, ea, sd = rec
    if start_cyc <= cyc <= end_cyc:
        records.append((n,cyc,pc,insn,rd,wv,st,ea,sd))
print('records=%d'%len(records))
for i,rec in enumerate(records):
    if rec[2] == VEC:
        n,cyc,pc,insn,rd,wv,st,ea,sd=rec
        print('VEC n=%d cyc=%d rd=%d wv=%08x ea=%08x head=%s' % (n,cyc,rd,wv,ea,'head' if wv==0 else 'nested'))
        for r in records[i+1:i+9]:
            n2,c2,pc2,i2,rd2,wv2,st2,ea2,sd2=r
            print('  %d cyc=%d pc=%08x insn=%08x rd=%2d wv=%08x st=%d ea=%08x sd=%08x' % (n2,c2,pc2,i2,rd2,wv2,st2,ea2,sd2))
        print()
