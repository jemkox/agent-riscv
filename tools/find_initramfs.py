import sys, gzip, re
p=sys.argv[1]
b=open(p,'rb').read()
for m in re.finditer(b'\x1f\x8b', b):
    off=m.start()
    tail=b[off:]
    try:
        data=gzip.decompress(tail)
        print(f'ok off={off} gzip_tail_len={len(tail)} decompressed_len={len(data)}')
    except Exception as e:
        best=None
        for cut in range(0, 8192):
            try:
                data=gzip.decompress(tail[:len(tail)-cut])
                best=(len(tail)-cut,len(data)); break
            except Exception:
                pass
        if best:
            print(f'valid off={off} gzip_len={best[0]} decompressed_len={best[1]}')
        else:
            print(f'bad off={off}')
    if off > 4500000:
        break
