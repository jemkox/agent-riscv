import sys
p=sys.argv[1]; off=int(sys.argv[2]); n=int(sys.argv[3])
b=open(p,'rb').read()
print('off', off)
print('bytes', b[off:off+n].hex())
for i,v in enumerate(b[off-16:off+16]):
    print(f'{off-16+i:08x}: {v:02x}', end=' ')
print()
