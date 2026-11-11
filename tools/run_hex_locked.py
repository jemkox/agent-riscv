#!/usr/bin/env python3
# Run a run_hex/Verilator runner without concurrent processes sharing p.hex or
# the mutable runner binary: BIN SRC_HEX OUT_LOG [TIMEOUT_SECONDS].
# The helper holds a directory lock while it copies both inputs and runs, so two
# concurrent hdl make invocations cannot read half-updated shared build files.
import os
import shutil
import subprocess
import sys
import time

def build_root_from_bin(binpath):
    # Runner binaries are built under $(B)/vlt*/<binary>. Prefer that path so
    # nested `make B=.../suite` jobs use the suite's own $(B)/p.hex, not the
    # parent BUILD_ROOT.
    parent = os.path.dirname(os.path.abspath(binpath))
    if os.path.basename(parent).startswith("vlt"):
        return os.path.dirname(parent)
    return os.environ.get("BUILD_ROOT", "build")

def safe_copy_exe(src, dst):
    last = None
    for _ in range(20):
        try:
            if os.path.exists(dst):
                os.remove(dst)
            shutil.copy2(src, dst)
            return None
        except OSError as e:
            last = e
            time.sleep(0.05)
    return last

def main(argv):
    if len(argv) not in (4, 5):
        print("usage: run_hex_locked.py BIN SRC_HEX OUT_LOG [TIMEOUT_SECONDS]")
        return 1
    binpath, src, out = argv[1:4]
    timeout = float(argv[4]) if len(argv) == 5 else None
    b = build_root_from_bin(binpath)
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
        err = safe_copy_exe(binpath, shared_bin)
        if err is not None:
            print("ERROR copying locked runner binary: " + str(err))
            return 1
        shutil.copy2(src, shared_hex)
        p = subprocess.Popen([shared_bin], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        try:
            data = p.communicate(timeout=timeout)[0]
            rc = p.returncode
        except subprocess.TimeoutExpired:
            p.kill()
            try:
                p.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            data = "ERROR: TIMEOUT %ss (locked runner)\n" % timeout
            rc = 1
        with open(out, "w") as f:
            f.write(data)
        return rc
    finally:
        try:
            os.rmdir(lock)
        except OSError:
            pass

if __name__ == "__main__":
    sys.exit(main(sys.argv))
