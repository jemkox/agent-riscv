import sys
import re

path = sys.argv[1]
text = open(path).read()
new = re.sub(r'(^|[^A-Za-z0-9_.$-])build/', r'\1$(B)/', text)
if 'B ?= build' not in new:
    new = new.replace('RVTEST_DIR ?=', 'B ?= build\nRVTEST_DIR ?=', 1)
open(path, 'w').write(new)
