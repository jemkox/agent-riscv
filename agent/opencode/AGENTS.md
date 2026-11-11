# Rules for the local agent

- Work inside @WORKSPACE@. Treat it as the project folder; do not read or change files elsewhere unless the user asks.
- Never touch disks or partitions, the bootloader, GRUB, EFI or /etc/fstab. Never handle disk-encryption recovery keys.
- sudo: allowed when a task really needs admin rights. Always write it as `sudo -A <command>` (the -A makes a password box appear for the user). It runs without an approval step but the password pop-up still needs the user; if it fails, carry on without it. Never try to obtain, read or handle the password. Still blocked (do not attempt): anything touching disks or partitions (dd, mkfs, fdisk, parted, wipefs, mount, /dev/sd*, /dev/nvme*), BitLocker/cryptsetup, the bootloader (GRUB, EFI, /boot, /etc/fstab), and ~/.ssh / ~/.gnupg.
- Downloads: only into @WORKSPACE@/downloads, from well-known official sources. Check the size first (`curl -sIL URL`) and mention what you downloaded in your final reply.
- Web: cite the URLs you used when you report research results.
- Never start a server bound to anything other than 127.0.0.1.
- If a tool call fails, read the error and fix the arguments. If the same approach keeps failing, try a different one instead of stopping.
- A failing test, failing simulation or lint error is NOT a failed tool call: it is normal work. Read the output, fix the design and rerun, as many times as needed. The stop-after-two rule is only for commands that are malformed or tools that are broken.

## HDL work (Verilog / SystemVerilog)
- The tools are installed and work: Icarus Verilog 12 (iverilog, vvp), Verilator 5.020 (lint AND full fast simulation: g++ is installed, use `verilator --binary` or `--cc --exe --build` from a Makefile), Yosys 0.33, nextpnr-ice40 + IceStorm (icepack, icetime) for iCE40 FPGA place-and-route and real Fmax, and the RISC-V toolchain riscv64-unknown-elf-gcc/as/objcopy/objdump with picolibc (`--specs=picolibc.specs`). Do not probe them with --help or which; just use them as shown below.
- Verilator is ~100x faster than Icarus: use it for long regressions and running compiled C programs; Icarus is fine for small unit tests. Run Verilator-built binaries from a Makefile target via `hdl make`.
- FPGA flow: `hdl yosys -p 'synth_ice40 -top <top> -json out.json' <files>` then `hdl nextpnr-ice40 --up5k --package sg48 --json out.json --asc out.asc --freq 50` (read the reported Max frequency) and `hdl icepack out.asc out.bin`.
- QEMU user-mode RISC-V (`hdl qemu-riscv32 prog.elf`, `hdl qemu-riscv64`): a known-correct reference CPU. Programs must be Linux-ABI static ELFs (exit with a7=93 ecall). `hdl qemu-riscv32 -d in_asm,cpu -D trace.log prog.elf` writes an instruction/register trace to compare against your RTL.
- Official RISC-V tests (read-only, already downloaded): @WORKSPACE@/downloads/riscv-tests (isa/rv32ui, rv32um, rv32mi, ...; env/ has the test macros) and @WORKSPACE@/downloads/riscv-arch-test (tests/rv32i/I, M, Zicsr, Zca, ...). Copy what you need into your project; do not edit the originals.
- Formal verification: `hdl sby -f job.sby` (SymbiYosys) with engine `smtbmc z3`. Do NOT use boolector (the installed version is too old and errors). riscv-formal is in @WORKSPACE@/downloads/riscv-formal.
- Verilator builds use ccache automatically (cache in @WORKSPACE@/.ccache), so rebuilds after small edits are fast.
- SDL2 is installed (`sdl2-config --cflags --libs`): a Verilator C++ testbench can open a window to show a framebuffer.
- Shell commands: never add redirections of any kind (2>/dev/null, 2>&1, > file). Any `>` makes the command wait for the user's approval.
- Run HDL tools ONLY through the sandbox wrapper `hdl`, from inside @WORKSPACE@: `hdl iverilog ...`, `hdl vvp ...`, `hdl verilator ...`, `hdl yosys ...`, `hdl make ...`, `hdl nextpnr-ice40 ...`, `hdl icepack ...`, `hdl icetime ...`, `hdl riscv64-unknown-elf-gcc ...`, `hdl qemu-riscv32 ...`, `hdl sby ...`. These run without asking; calling the tools directly asks the user. The sandbox has no network and can only write inside @WORKSPACE@. `hdl` already shows error output: never add `2>&1` or other redirections (they make the command ask the user); a plain `| head` or `| tail` is fine.
- Put each design in its own folder (e.g. hdl/<name>/) with the RTL, a testbench and a Makefile or run commands.
- Always write a self-checking testbench: compare outputs against expected values, count errors, and print exactly `TEST PASSED` or `TEST FAILED: <n> errors` at the end.
- Before saying a design works: lint it (`hdl verilator --lint-only -Wall <files>`), simulate it (`hdl iverilog -g2012 -o sim.vvp <files>` then `hdl vvp sim.vvp`), and report the real output. Never claim a pass you did not see.
- Icarus: use `-g2012` for SystemVerilog. Write waveforms with `$dumpfile("wave.vcd"); $dumpvars;` so the user can open them in GTKWave.
- Write synthesizable RTL: no delays (#) or initial blocks in RTL modules, non-blocking (<=) in clocked always blocks, blocking (=) in combinational ones, a defined reset, no latches (`always_comb` / full case defaults). Check with `hdl yosys -q -p 'read_verilog -sv <files>; synth -top <top>'` when asked about synthesis.
- Keep a short notes.md in the design folder: what was built, how to run it, last test result.

## Work autonomously (no explanation notes)
- Do not write "what I'm about to do" notes, plans or status summaries before or between actions. Just act.
  Everything you do (each command, edit and commit) is logged for the user automatically.
- While working on a task, every reply must contain at least one tool call. A reply with only text ends your
  turn; you will then be nudged to continue.
- Failing tests and errors are normal work: read them, fix, rerun.
- Never wait for approval; nothing needs it. If something is denied, find another way.
- `sudo -A apt install ...` is allowed when a package is really missing; it needs the user's password in a
  pop-up, so if it fails or times out, continue with what is installed and note what was missing.
- For any task with more than a couple of steps, keep a checklist in `TODO.md` in the project's folder:
  `- [x] done step`, `- [~] step in progress`, `- [ ] next step`. Update it as you go (it survives context
  compaction, and the user's sidebar shows it as the Plan). Projects that list milestones in PROMPT.md and
  commit them as `M3: ...` are tracked automatically and do not need TODO.md.
- When the user's task is fully done, end your final reply with a line `TASK COMPLETE`.
  If you truly cannot continue without the user, end with a line `NEED USER: <one short question>`.
  Only these two lines stop the automatic nudges.
