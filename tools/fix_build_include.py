import sys
path = sys.argv[1]
text = open(path).read()
old = "-Ibuild/"
new = "-I$(B)/"
open(path, "w").write(text.replace(old, new))
