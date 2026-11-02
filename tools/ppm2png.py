import sys
from PIL import Image

for pair in sys.argv[1:]:
    src, dst = pair.split('=')
    im = Image.open(src)
    im.save(dst)
    print(f'{src} -> {dst}')
