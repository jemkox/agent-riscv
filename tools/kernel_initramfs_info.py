import sys, zlib
p=sys.argv[1]; off=int(sys.argv[2])
b=open(p,'rb').read()
offz=zlib.decompressobj(-15)
data=offz.decompress(b[off+10:])
print('decompressed', len(data), 'unused', len(offz.unused_data), 'header', b[off:off+10].hex())
# compressed length = total tail len - unused - trailer 8? unused_data starts at trailer? For raw deflate, unused includes trailer?
# Gzip has CRC+size trailer after deflate. raw decompressor may include trailer as unused.
# Try to locate valid trailer: unused starts with crc le32 isize le32.
for cut in range(0, min(len(offz.unused_data), 1024)):
    tail=offz.unused_data[:cut]
    if len(tail)==8:
        import struct
        crc, isize=struct.unpack('<II', tail)
        print('crc',crc,'isize',isize)
    break
