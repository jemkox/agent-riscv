#!/usr/bin/env python3
# Probe QEMU virt's synthesized ROM stub (0x1000) + fw args struct via QMP.
import subprocess, socket, json, time, sys, os

QMP = sys.argv[1] if len(sys.argv) > 1 else os.path.relpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build-linux", "mmu3", "qmp.sock"))
try:
    os.unlink(QMP)
except FileNotFoundError:
    pass

p = subprocess.Popen(
    ["hdl", "qemu-system-riscv32", "-S", "-M", "virt", "-m", "64M",
     "-nographic",
     "-chardev", "socket,id=qmp0,path=%s,server=on" % QMP,
     "-bios", "../../build-linux/mmu3/images/fw_jump.bin",
     "-kernel", "../../build-linux/mmu3/images/Image",
     "-initrd", "../../build-linux/mmu3/images/rootfs.cpio"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def rpc(s, o):
    s.sendall(json.dumps(o).encode())
    buf = b""
    while True:
        d = s.recv(65536)
        if not d:
            raise EOFError
        buf += d
        try:
            return json.loads(buf.decode())
        except Exception:
            pass

s = None
for _ in range(100):
    try:
        s = socket.socket(socket.AF_UNIX)
        s.connect(QMP)
        break
    except Exception:
        time.sleep(0.2)
if s is None:
    print("NO SOCKET"); p.terminate(); sys.exit(1)

rpc(s, {"execute": "qmp_capabilities"})
for cmd in ["x/64xw 0x1000", "xp /80xh 0x1000"]:
    r = rpc(s, {"execute": "human-monitor-command",
               "arguments": {"command-line": cmd}})
    print(r.get("return", ""))
s.close()
p.terminate()
