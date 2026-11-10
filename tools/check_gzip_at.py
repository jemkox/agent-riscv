import sys, gzip
p=sys.argv[1]; off=int(sys.argv[2])
b=open(p,'rb').read()
tail=b[off:]
try:
    data=gzip.decompress(tail)
    print('tail ok', len(tail), len(data))
except Exception as e:
    print('tail fail', e)
best=None
for cut in range(0, 20000):
    try:
        data=gzip.decompress(tail[:len(tail)-cut])
        best=(len(tail)-cut, len(data)); break
    except Exception:
        pass
print(best)
if best:
    print(b[best[0]:best[0]+40])
