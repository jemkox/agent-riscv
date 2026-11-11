import hashlib
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# Parallel-ish regress runner: per-seed gen -> sim (single prebuilt run_hex fed
# via build/p.hex, 60s limit) -> ISS --pass (30s) -> cmp.  Seeds whose .bin hash
# matches a stored hash and whose cmp passed before are skipped.
N = int(sys.argv[1]) if len(sys.argv) > 1 else 500
B = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("BUILD_ROOT", "build")
LAT = int(sys.argv[3]) if len(sys.argv) > 3 else 1   # CACHE_LAT of the run_hex build
BIN = os.path.join(B, "vlt", "run_hex_lat%d" % LAT)
RD = os.path.join(B, "rand")
os.makedirs(RD, exist_ok=True)

STATE = os.path.join(RD, ".state")
prev = {}
if os.path.exists(STATE):
    with open(STATE) as f:
        for ln in f:
            k, _, v = ln.partition(" ")
            prev[k.strip()] = v.strip()

todo = []
for i in range(1, N + 1):
    gen = subprocess.run(["python3", "tools/gen.py", str(i), os.path.join(RD, "p%d" % i)],
                         capture_output=True, text=True)
    if gen.returncode != 0:
        print("gen fail seed %d: %s" % (i, gen.stderr.strip()[:120]))
        continue
    bpath = os.path.join(RD, "p%d.bin" % i)
    h = hashlib.sha1(open(bpath, "rb").read()).hexdigest()
    st = os.path.join(RD, "p%d.state2" % i)
    if prev.get("%d_lat%d" % (i, LAT)) == h and os.path.exists(os.path.join(RD, "%d_lat%d.rtl.ok" % (i, LAT))):
        continue
    todo.append((i, h))

print("to-run %d seeds" % len(todo), flush=True)
fails = []
simfail = []
for n, (i, h) in enumerate(todo):
    rtl_log = os.path.join(RD, "%d.rtl.log" % i)
    helper_out = os.path.join(RD, "%d.helper.log" % i)
    try:
        r = subprocess.run([sys.executable, "tools/run_hex_locked.py", BIN,
                            os.path.join(RD, "p%d.hex" % i), rtl_log],
                           capture_output=True, text=True, timeout=70)
        open(helper_out, "w").write(r.stdout + r.stderr)
        if r.returncode != 0 or not os.path.exists(rtl_log) or "#NOTERM" in open(rtl_log).read():
            fails.append((i, "SIM NOTERM/helper failure rc=%d (stuck pipeline)" % r.returncode))
            continue
    except subprocess.TimeoutExpired:
        simfail.append((i, "SIM TIMEOUT 70s (locked helper)"))
        continue
    open(os.path.join(RD, "p%d.state2" % i), "w").write(h)
    if (n + 1) % 100 == 0:
        print("... sim %d/%d" % (n + 1, len(todo)), flush=True)

def verify(t):
    i = t
    r = subprocess.run(["python3", "iss/iss.py", "--quiet",
                        "--log", os.path.join(RD, "%d.iss.log" % i),
                        os.path.join(RD, "p%d.bin" % i)],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        return (i, "ISS --pass rc=%d" % r.returncode)
    c = subprocess.run(["python3", "tools/cmp.py", os.path.join(RD, "%d.rtl.log" % i),
                        os.path.join(RD, "%d.iss.log" % i)],
                       capture_output=True, text=True)
    if c.returncode != 0:
        return (i, "CMP FAIL " + (c.stdout + c.stderr).strip().replace("\n", " ")[:160])
    open(os.path.join(RD, "%d_lat%d.rtl.ok" % (i, LAT)), "w").write("1")
    return (i, "ok")

verified_ok = set()
with ThreadPoolExecutor(max_workers=8) as ex:
    for i, m in ex.map(verify, [t[0] for t in todo]):
        if m == "ok":
            verified_ok.add(i)
        else:
            fails.append((i, m))

for i, m in simfail + fails:
    print("SEED %d: %s" % (i, m))
with open(STATE, "w") as f:
    todo_ids = {i for i, _ in todo}
    for k, v in prev.items():
        if int(k.split("_lat")[0]) not in todo_ids:
            f.write("%s %s\n" % (k, v))
    for i, h in todo:
        if i in verified_ok:
            f.write("%d_lat%d %s\n" % (i, LAT, h))
if simfail or fails:
    print("REGRESS FAILED: %d seeds" % (len(simfail) + len(fails)))
    raise SystemExit(1)
print("REGRESS ALL PASS (%d checked, %d skipped)" % (len(todo), N - len(todo)))
