import sys
p=sys.argv[1]; name=sys.argv[2]
data=open(p,'rb').read(); i=0
while True:
    if data[i:i+6] not in (b'070701',b'070702',b'070707'): break
    size=int(data[i+54:i+62],16); nsize=int(data[i+94:i+102],16)
    nm=data[i+110:i+110+nsize-1].decode('ascii','replace')
    h=i+110+nsize; body=h+((-h)%4)
    if nm==name:
        print('off',body,'size',size)
        print(data[body:body+min(size,400)])
    if nm=='TRAILER!!!': break
    end=body+size+((-size)%4)
    i=end
