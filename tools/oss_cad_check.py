#!/usr/bin/env python3
# Check pinned OSS CAD Suite files required by fpga_tang.
# Usage: oss_cad_check.py ROOT [VERSION YOSYS_SHA NEXT_PNR_SHA GOWIN_SHA]...
# The Makefile passes the pinned version/shas from variables.
import hashlib
import os
import sys

def sha256(path):
    if not os.path.exists(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def main(argv):
    if len(argv) < 2:
        print("missing OSS_CAD root: pass fpga_tang OSS_CAD=/abs/path/to/oss-cad-suite-VERSION")
        return 1
    root = argv[1]
    want_version = os.environ.get("OSS_CAD_VERSION", "")
    want = {
        "yosys": os.environ.get("OSS_CAD_YOSYS_SHA256", ""),
        "nextpnr-himbaechel": os.environ.get("OSS_CAD_NEXT_PNR_HIMBAECHEL_SHA256", ""),
        "gowin_pack": os.environ.get("OSS_CAD_GOWIN_PACK_SHA256", ""),
    }
    for i in range(2, len(argv), 2):
        want[argv[i]] = argv[i+1]
    if not os.path.isdir(root):
        print(f"ERROR: pinned OSS CAD Suite not found at {root}")
        print("Install it under deps/oss-cad-suite or pass OSS_CAD=/abs/path to fpga_tang.")
        print("Pinned version expected: " + (want_version or ""))
        return 1
    ver = os.path.join(root, "VERSION")
    if not os.path.exists(ver):
        print(f"ERROR: missing VERSION file in {root}")
        return 1
    got_ver = open(ver).read().strip()
    if want_version and got_ver != want_version:
        print(f"ERROR: OSS CAD Suite VERSION mismatch: got {got_ver}, want {want_version}")
        return 1
    bad = []
    for tool, want_sha in want.items():
        p = os.path.join(root, "bin", tool)
        got = sha256(p)
        if got is None:
            bad.append(f"{tool}: missing {p}")
        elif want_sha and got != want_sha:
            bad.append(f"{tool}: sha256 mismatch got {got} want {want_sha}")
    if bad:
        print("ERROR: pinned OSS CAD Suite tools mismatch:")
        for b in bad:
            print("  " + b)
        return 1
    print(f"OSS CAD Suite pin OK: {root} version={got_ver} yosys/nextpnr-himbaechel/gowin_pack sha256 matched")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
