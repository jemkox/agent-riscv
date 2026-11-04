import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("| build", "| $(B)")
text = text.replace("-p build", "-p $(B)")
open(path, "w").write(text)
