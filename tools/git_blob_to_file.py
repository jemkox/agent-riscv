#!/usr/bin/env python3
# tools/git_blob_to_file.py <blob-or-commit:path> <out.bin>
# Writes a git blob to a file without shell redirection.
import sys, subprocess, pathlib
if len(sys.argv)<3:
    raise SystemExit("usage: tools/git_blob_to_file.py <git-rev:path> <out.bin>")
pathlib.Path(sys.argv[2]).write_bytes(subprocess.run(["git","cat-file","blob",sys.argv[1]], check=True, stdout=subprocess.PIPE).stdout)
