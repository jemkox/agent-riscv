# PROGRESS

## M1: single-cycle RV32I CPU

### Worked
- RTL modules: `rtl/top_single.sv`, `rtl/ctrl.sv`, `rtl/imm32.sv`, `rtl/alu.sv`, `rtl/mem32.sv`, `rtl/regs32.sv`.
- Testbench: `tb/run_hex.sv` logs retired instructions as `pc insn rd value store_flag store_addr store_data store_mask`.
- Directed tests passed: `t01_basic`, `t02_memory`, `t03_control`, `t04_edge`, `t05_jumps`, `t06_fence`.
- Random differential regression passed for 500 generated RV32I programs.
- Python ISS (`iss/iss.py`) and random generator (`tools/gen.py`) were fixed for the 8-field log format, memory/log store rules, and corrected RV32I encodings.
- Verilator loader fix: the testbench now sets `lwe/lwa/lwd` one time unit before the loader port is committed by `clk`, so Verilator sees the current word instead of the previous/zero value.

### Failed / fixed
- Initial random Verilator regression failed with first retired instruction zero.
  - Root cause: testbench assigned loader inputs in the same zero-time instant as `clk=1`; Verilator's `mem32` clocked write can run before those assignments.
  - Fix: set loader inputs first, `#1`, then commit `clk`.

### How to run
```sh
hdl make test
hdl make regress N=500
hdl make lint
hdl make synth
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M1 | 6 directed + 500 random | ~1.00 | 8717 (16-word RAM proof variant) | n/a |

### Synthesis proof
- Yosys command uses a 16-word `mem32_small.sv` variant for fast latch checking.
- Result: no errors, no latches, 8717 total cells in the proof design.

### Honest limitations
- M1 is single-cycle and supports RV32I directed/random programs plus fence/system halt behavior; no M extension, CSR, cache, pipeline, or FPGA build yet.
- Official riscv-tests are pending.

### Next step
- M2: 5-stage pipeline, forwarding, load-use stall, branch flush; switch regression to Verilator and run 5000+ random programs.
