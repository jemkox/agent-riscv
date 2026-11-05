#!/usr/bin/env python3
# Prune vendored FreeRTOS-Kernel to the files this build actually compiles/needs.
# Usage: prune_freeRTOS.py [--delete] [ROOT]
import os, sys
def keep(rel):
    p = rel.replace("\\", "/")
    if p == "manifest.yml" or p == "LICENSE.md" or p == "README.md":
        return True
    if p.startswith("include/"):
        return True
    if p in ("tasks.c", "queue.c", "list.c", "timers.c"):
        return True
    if p == "portable/MemMang/heap_4.c":
        return True
    if p.startswith("portable/GCC/RISC-V/"):
        return True
    return False
def main(argv):
    delete = False
    root = "deps/FreeRTOS-Kernel"
    for a in argv[1:]:
        if a == "--delete": delete = True
        else: root = a
    removed = kept = 0
    for dirpath, _, files in os.walk(root, topdown=False):
        for f in files:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root)
            if keep(rel):
                kept += 1
            else:
                removed += 1
                if delete:
                    try:
                        os.remove(p)
                    except FileNotFoundError:
                        pass
    for dirpath, dirs, _ in os.walk(root, topdown=False):
        for d in dirs:
            p = os.path.join(dirpath, d)
            rel = os.path.relpath(p, root)
            if not any(keep(os.path.relpath(os.path.join(p, x), root)) for x in os.listdir(p)):
                removed += 1
                if delete:
                    try:
                        os.rmdir(p)
                    except OSError:
                        pass
    print(f"kept={kept} removed={removed}")
    return 0
if __name__ == "__main__": sys.exit(main(sys.argv))
