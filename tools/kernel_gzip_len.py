import sys, zlib, struct
p=sys.argv[1]; off=int(sys.argv[2])
b=open(p,'rb').read()
tail=b[off:]
o=zlib.decompressobj(-15)
data=o.decompress(tail[10:])
unused=o.unused_data
print('unused first16', unused[:16].hex())
crc, isize = struct.unpack('<II', unused[:8])
print('crc', hex(crc), 'isize', isize)
# trailer is 8 bytes starting at compressed end; so raw deflate consumed length = len(tail)-10-len(unused)
deflate_len = len(tail)-10-len(unused)
print('gzip_len', 10 + deflate_len + 8)
print('end_off', off + 10 + deflate_len + 8)
