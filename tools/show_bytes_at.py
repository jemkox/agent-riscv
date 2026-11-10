import sys
p=sys.argv[1]; off=int(sys.argv[2]); n=int(sys.argv[3])
b=open(p,'rb').read()
print(f'off={off}')
print(b[off:off+n].hex())
try:
    print(b[off], b[off+1])
except Exception:
    pass
