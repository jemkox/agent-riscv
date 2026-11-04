import argparse
import concurrent.futures
import os
import subprocess

def suite(name, make_args):
    bdir = os.path.join(os.environ.get("BUILD_ROOT", "build"),
                        "all_tests_parallel", name)
    return name, ["hdl", "make", "B=" + bdir] + list(make_args)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="build")
    ap.parse_args()
    root = os.environ.get("BUILD_ROOT")

    specs = [
        ("test", "[1/6] test (CACHE_LAT=1)", ["test"]),
        ("test_lat5", "[2/6] test CACHE_LAT=5", ["CACHE_LAT=5", "test"]),
        ("ui_um_mi", "[3/6] ui um mi", ["ui", "um", "mi"]),
        ("regress", "[4/6] regress N=500", ["regress", "N=500"]),
        ("m7", "[5/6] m7", ["m7"]),
        ("doom", "[6/7] doom (31 frames)", ["doom"]),
        ("mpp_ret", "[7/7] mpp_ret_gate (ISS mret MPP + RTL LINUX_MPP + standard mirror)", ["mpp_ret_test", "mpp_ret_gate"]),
    ]
    jobs = [(name, label, ["hdl", "make", "B=" + os.path.join(os.environ.get("BUILD_ROOT", "build"), "all_tests_parallel", name)] + args)
            for name, label, args in specs]
    outputs = {}
    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(jobs))) as ex:
        future_to_name = {ex.submit(run, cmd): name for name, _label, cmd in jobs}
        for fut in concurrent.futures.as_completed(future_to_name):
            name = future_to_name[fut]
            out = fut.result()
            outputs[name] = out
            if out["rc"] != 0:
                failed.append(name)

    for name, label, _cmd in jobs:
        print("== " + label + " ==")
        out = outputs[name]
        print(out["stdout"].rstrip())
        if out["stderr"]:
            print(out["stderr"].rstrip())
        if out["rc"] != 0:
            print(f"SUITE FAILED: {name} rc={out['rc']}")
    if failed:
        print("ALL TESTS DONE" if False else "TEST FAILED: " + ", ".join(failed))
        raise SystemExit(1)
    print("ALL TESTS DONE")

def run(cmd):
    proc = subprocess.run(cmd, cwd=os.getcwd(), capture_output=True, text=True)
    return {"rc": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}

if __name__ == "__main__":
    main()
