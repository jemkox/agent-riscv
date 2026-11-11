#!/usr/bin/env python3
# Run a run_hex/Verilator runner without concurrent processes sharing p.hex or
# the mutable runner binary: BIN SRC_HEX OUT_LOG.
# The helper holds a directory lock while it copies both inputs and runs, so two
# concurrent hdl make invocations cannot read half-updated shared build files.
import os
import shutil
import subprocess
import sys
import time

def main(argv):
    if len(argv) != 4:
        print("usage: run_hex_locked.py BIN SRC_HEX OUT_LOG")
        return 1
    binpath, src, out = argv[1:4]
    b = os.environ.get("BUILD_ROOT", "build")
    shared_hex = os.path.join(b, "p.hex")
    shared_bin = os.path.join(b, "vlt", "run_hex.locked.bin")
    lock = os.path.join(b, "run_hex.lock")
    os.makedirs(os.path.dirname(shared_bin), exist_ok=True)
    for _ in range(1000):
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            time.sleep(0.05)
    else:
        print("ERROR: stale run_hex lock: " + lock)
        return 1
    try:
        shutil.copy2(binpath, shared_bin)
        shutil.copy2(src, shared_hex)
        with open(out, "w") as f:
            r = subprocess.run([shared_bin], stdout=f, stderr=f, text=True)
        return r.returncode
    finally:
        try:
            os.rmdir(lock)
        except OSError:
            pass

if __name__ == "__main__":
    sys.exit(main(sys.argv))
