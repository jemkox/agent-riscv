import sys, zlib, struct
p=sys.argv[1]; off=int(sys.argv[2])
b=open(p,'rb').read()
o=zlib.decompressobj(-15)
data=o.decompress(b[off+10:])
unused=o.unused_data
print('decompressed len',len(data),'unused len',len(unused))
for k in range(0, min(len(unused), 1024)):
    if k+8 <= len(unused):
        crc,isize=struct.unpack('<II', unused[k:k+8])
        if zlib.crc32(data)==crc and (len(data)&0xffffffff)==isize:
            end=off+10+(len(b)-off-10-len(unused))+k+8
            print('end',end,'deflate_len',end-off-18,'unused_offset',k)
            break
print(b[off:off+10].hex())
