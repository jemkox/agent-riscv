# PROGRESS

## RULES
- Keep working until the final acceptance test is actually proven; a failing simulation, test, lint, or timing check is normal work, not a stopped task.
- Stop after two failed attempts only when the command/tool itself is broken; simulation failures should be read, fixed, and rerun.
- Prefer small targeted edits and keep each source file around 250 lines when possible.
- Run HDL/simulator/build tools through the `hdl` wrapper: `hdl make`, `hdl verilator`, `hdl iverilog`, `hdl vvp`, `hdl yosys`, etc.
- Do not use shell redirections in direct commands; piping to `head`/`tail` is okay.
- Use official riscv-tests only from the already-available local read-only copies. Do not clone/download extra test suites.

## M1: single-cycle RV32I CPU

### Worked
- RTL modules: `rtl/top_single.sv`, `rtl/ctrl.sv`, `rtl/imm32.sv`, `rtl/alu.sv`, `rtl/mem32.sv`, `rtl/regs32.sv`.
- Testbench: `tb/run_hex.sv` logs retired instructions as `pc insn rd value store_flag store_addr store_data store_mask`.
- Directed tests passed: `t01_basic`, `t02_memory`, `t03_control`, `t04_edge`, `t05_jumps`, `t06_fence`.
- Random differential regression passed for 500 generated RV32I programs.
- Official `rv32ui` passed on M1: `make ui` built 42 official `.S` tests and reported `ALL UI PASS`; 42 RTL logs and 42 ISS logs exist under `build/ui/logs/`.
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
## M2: five-stage pipeline RV32I CPU

### Worked
- Added `rtl/top_pipe.sv`: IF/ID, ID/EX, EX/MEM, MEM/WB stages with forwarding, load-use stall, branch/JAL/JALR flush, ebreak/system stop, and `rv_valid` retire logging.
- Added a second decoder (`CEID` in `top_pipe.sv`) for IF/ID operands so forwarding can be applied when operands are latched into ID/EX.
- Directed tests passed under pipeline: `t01_basic`, `t02_memory`, `t03_control`, `t04_edge`, `t05_jumps`, `t06_fence`.
- Verilator differential regression passed for 200 generated RV32I programs.
- Official `rv32ui` passed with pipeline: `ALL UI PASS` (42 tests).

### Failed / fixed
- Initial pipeline failures used stale operands for instructions whose producer had just retired into MEM/WB or was in EX/MEM.
  - Fix: added EX/MEM and MEM/WB forwarding at ID/EX capture and in current ID/EX ALU operand selection.
  - Fix: `read_b` now includes register-reading R-type OP (`ce_op`), not only branch/store, so load-use hazards and second-operand forwarding are detected.

### How to run
```sh
hdl make test
hdl make regress N=200
hdl make ui
hdl make lint
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M2 | 6 directed + 5000 random + 42 UI | 0.873 | 16768 (small RAM proof variant) | n/a |

### Formal proof
- Added `formal/pipe_check.sv` and `formal/pipeline.sby`.
- `hdl sby -f formal/pipeline.sby` from the `formal/` directory passes k-induction in `mode prove`.
- Proved compact inductive invariants: PC alignment, no simultaneous stall/flush, valid-stage PC alignment, and architectural x0 writes cannot make x0 nonzero.
- The full top-level pipeline memory proof was too slow with z3; this is a model-level proof of the pipeline invariants, not full equivalence to `top_pipe.sv`.

### Honest limitations
- M2 currently targets simulation RV32I behavior and official UI pass; FPGA synthesis of the full pipeline RAM has not been evaluated as the M1 synthesis proof used a small RAM variant.
- M extension, CSR, cache, UART, and FPGA build are not yet included.
- Formal verification proves the compact model-level invariants, not full equivalence of every pipeline bit.

## M3: RV32M/RV32IM pipeline CPU

### Worked
- Added RV32M decode in `rtl/ctrl.sv`: `is_m` and `m_op` select `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`, `rem`, and `remu`.
- Added multi-cycle `rtl/mdiu.sv` integrated into `rtl/top_pipe.sv` for M result capture, stall, and forwarding.
- Fixed `rtl/top_pipe.sv` Icarus issue: `md_result` is declared without a constant initializer.
- Fixed signed high-product correction in `rtl/mdiu.sv`: the `a_ext << 32` subtract is applied only when multiplier bit 31 is set.
- Added directed M test `tests/t07_m.S`; `make test` now covers `t01_basic`, `t02_memory`, `t03_control`, `t04_edge`, `t05_jumps`, `t06_fence`, and `t07_m`.
- Updated ISS `iss/iss.py` to execute RV32M, including signed/unsigned division, remainder, high products, divide-by-zero, and `INT_MIN / -1`.
- Updated `tools/gen.py` to generate RV32IM random programs including M instructions.
- Added official `rv32um` target in `Makefile` using `../../downloads/riscv-tests/isa/rv32um` and `rv32im_zifencei` compile flags.
- `make test` passed all 7 directed tests, including `t07_m`.
- `make regress N=50` and `make regress N=200` passed.
- `make regress N=5000` passed and printed `ALL PASS`.
- `make um` passed all 8 official RV32UM tests and printed `ALL UM PASS`.
- `make ui` passed all 42 official RV32UI tests and printed `ALL UI PASS`.
- Measured UI aggregate from RTL logs: `12389 instrs / 14191 cycles`, IPC `0.873`.
- `make lint` passed.
- `make synth` passed Verilator lint for pipeline and single-cycle tops, then Yosys synthesis of `top_pipe` with `mem32_small.sv`.
- Pipeline+M synthesis proof hierarchy cells: `21294`.

### Failed / fixed
- Initial `make test` M failure showed `mulh` RTL high product `0x00000006` instead of ISS `0xffffffff` for `0xdeadbeef * 0xdeadbeef`.
  - Fix: corrected signed multiplier correction in `rtl/mdiu.sv`.
- `rv32um` compile failed with `rv32um_zifencei` because the GCC arch parser rejected the first ISA subset.
  - Fix: use `rv32im_zifencei` for `UM_CCFLAGS`.
- Official `rv32um` runner initially failed because make removed intermediate UM `.bin` files after building `.hex`.
  - Fix: make `um`, `ui`, and directed `test` targets directly depend on their `.bin` targets so those binaries are not intermediate.
- `make synth` initially failed with missing `ctrl` output pins `is_m` and `m_op` in `top_single`.
  - Fix: declared `is_m` in `rtl/top_single.sv`, connected the new outputs, and excluded M instructions from single-cycle writeback with `!is_m`.
- `make synth` later failed because unused `rtl/mdiu.sv` in `RTL_SINGLE` created multiple top modules.
  - Fix: `RTL_SINGLE` no longer includes `rtl/mdiu.sv`, which is only used by `top_pipe`.

### How to run
```sh
hdl make test
hdl make regress N=5000
hdl make ui
hdl make um
hdl make lint
hdl make synth
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M3 | 7 directed + 5000 random + 42 UI + 8 UM | 0.873 | 21294 (small RAM proof variant) | n/a |

### Synthesis proof
- Yosys command uses the 16-word `mem32_small.sv` proof variant and synthesizes `top_pipe`.
- Result: no errors, no latches, `21294` total cells in the hierarchy with the pipeline, controller, ALU, M unit, small RAM, and register file.
- Yosys timing/Fmax not run in this target; Fmax metric remains `n/a`.

### Honest limitations
- M3 is verified in the five-stage pipeline design. The single-cycle top decodes M and prevents M writeback, but it does not execute M instructions and is not expected to pass RV32UM tests.
- The synthesis cell count is the small-RAM proof variant used by `make synth`, not the full simulator RAM.
- Formal proof is still model-level pipeline invariants from M2; M execution formal equivalence is not yet proven.

## M4: Branch predictor

### Worked
- Added a fetch-time BTB + 2-bit saturating-counter predictor in `rtl/btb.sv`: 64 direct-mapped entries indexed by `pc[7:2]`, tagged with `pc[31:8]`.
- Conditional branches are predicted taken only when the 2-bit counter is `3`; `JAL` is predicted taken; `JALR` is predicted taken only when a valid BTB target exists.
- Moved fetch branch/jump classification into `rtl/ifdec.sv` and predictor target selection into `rtl/bpif.sv`, keeping `rtl/top_pipe.sv` under the file-size target at 243 lines.
- Split pipeline helpers into `rtl/branch.sv`, `rtl/store.sv`, `rtl/ldext.sv`, `rtl/ldst.sv`, and `rtl/fwd.sv`.
- Added directed branch-predictor test `tests/t08_bp.S`; `make test` now includes `t08_bp`.
- Fixed a branch-prediction inversion in `rtl/branch.sv`: an actual not-taken branch with a predicted-taken path is a misprediction (`wrong_pred = branch_is && pred_taken`).
- Removed the redundant `ifdef FORMAL` block from `rtl/top_pipe.sv` after the split; the model-level proof target remains `formal/pipe_check.sv`.
- `make lint` passes for the pipeline top with `top_pipe`, BTB, predictor helpers, and forwarding helpers.
- `make test`, `make regress N=5000`, `make ui`, and `make um` pass after the split.
- Measured M4 UI totals from RTL logs: `12389 instrs / 13937 cycles`, IPC `0.889`.
- Measured M4 UI branch stats: `BR=2187`, predicted taken `129`, mispredictions `503`, accuracy `77.000%`.
- Measured M4 UM totals from RTL logs: `1917 instrs / 9698 cycles`, IPC `0.198`.
- Measured M4 UM branch stats: `BR=302`, predicted taken `0`, mispredictions `68`, accuracy `77.483%`.
- Measured M4 synthesis proof variant: `34491` total cells in the small-RAM pipeline hierarchy.

### Failed / fixed
- The branch-predictor split exposed an inverted wrong-prediction condition for not-taken branches. Before the fix, directed `t03_control` and `t08_bp` could retire wrong PC paths after an actual not-taken branch predicted taken.
- A first attempt to move both fetch decode and predictor target selection into one `bpif.sv` created Verilator `UNOPTFLAT` circular combinational logic because `ifdec` outputs fed BTB query while BTB query outputs fed predictor selection.
- Fix: split decode into `rtl/ifdec.sv` and target selection into `rtl/bpif.sv`, keeping the dependency acyclic.

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M4 | 8 directed + 5000 random + 42 UI + 8 UM | 0.889 UI, 0.198 UM | 34491 (small RAM proof variant) | n/a |

### Honest limitations
- M4 predictor accuracy is measured from the local RV32UI and RV32UM logs, not SPEC or benchmark suites.
- The UM IPC is low because the current multi-cycle M unit dominates those tests; the predictor still helps the UI mix.
- Synthesis count is the small-RAM proof variant from `make synth`, not the full simulator memory.
- Formal verification remains model-level pipeline invariants from M2; branch-predictor equivalence is not yet proven.

## M5: Zicsr, machine-mode traps, counters, timer, xhalt

### Worked
- Added CSR/SYSTEM decode flags in `rtl/ctrl.sv`: Zicsr `is_csr`, SYSTEM ECALL/EBREAK classification, illegal SYSTEM, and FENCE handling.
- Added `rtl/csrs.sv`: CSR register state, `mstatus`, `mtvec`, `mepc`, `mcause`, `mcycle`, `minstret`, `mtime`, `mtimecmp`, `xhalt`, counters, and trap/halt state.
- Added `rtl/csrs_pipe.sv`: wraps CSR read/write/retire, idex-stage CSR old-value read, trap mode, timer flush, trap flush, and `xhalt` halt output.
- Refactored `rtl/top_pipe.sv` to call `csrs_pipe` and split combinational blocks so `stall`/`m_stall` do not depend on trap outputs; current file is 244 lines.
- Added `rtl/fetch_pred.sv`: wraps `ifdec`, BTB, and branch prediction target selection; top file remains under 250 lines.
- Added CSR operand forwarding through `rtl/ctrl.sv`, `rtl/regs32.sv`, `rtl/fwd.sv`, and `idex_r1_cs` path in `rtl/top_pipe.sv`.
- Added directed tests `t09_csr`, `t10_ecall`, `t11_ebreak`, `t12_illegal`, and `t13_timer`.
- Updated `iss/iss.py` for Zicsr semantics, machine traps, timer traps, `mstatus`, `mepc`, `mcause`, `mtvec`, `mtimecmp`, `mtime` as read-only `mcycle`, and `xhalt` stop behavior.
- `make test` passes 13 directed tests, including all M5 CSR/trap/timer tests.
- `make ui` passes all 42 official RV32UI tests.
- `make um` passes all 8 official RV32UM tests.
- `make regress N=5000` passes and prints `ALL PASS`.
- `make lint` passes with no warnings for the new helpers.
- `make synth` passes; Yosys small-RAM `top_pipe` synthesis reports `38467` cells and no latches.
- Measured UI aggregate from RTL logs: `12389 instrs / 13937 cycles`, IPC `0.889`.
- Measured UM aggregate from RTL logs: `1917 instrs / 9698 cycles`, IPC `0.198`.

### Failed / fixed
- The first `mstatus`/trap handling created Verilator `UNOPTFLAT` cycles because counter/mstatus/halt updates depended on `trap_en`, while trap enable depended on stale current CSR state.
  - Fix: compute `after_mcycle`, `after_minstret`, `after_mtimecmp`, `mstatus_next`, and `halt_wr` in a trap-independent block; expose `mc_next`, `mtcmp_next`, `mstatus_next`, and `halt_out` through the helper.
- The timer test initially fired late because top used stale `cs_mtimecmp`/`cs_mstatus` while the next CSR state was being written in the same cycle.
  - Fix: timer uses `mc_next >= mtcmp_next`; top trap mode uses `mstatus_next[11]`.
- After `xhalt`, an extra retire line appeared because the top still used the old halt state rather than the halt produced by the current `xhalt` write.
  - Fix: `halt_out` is now `halt_wr`, and top `halt <= halt || exmem_stop || halt_out`.
- Splitting helper modules initially exposed unused helper inputs and width mismatches; removed unused `alu_res`/`idex_pred_tgt` helper inputs and fixed `exmem_r1` as 32-bit.
- Helper refactoring initially created Verilator cycles through combined top `always_comb` blocks; split top logic so `stall`/`m_stall` are independent of branch/trap/CSR outputs.

### How to run
```sh
hdl make test
hdl make ui
hdl make um
hdl make regress N=5000
hdl make lint
hdl make synth
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M5 | 13 directed + 5000 random + 42 UI + 8 UM | 0.889 UI, 0.198 UM | 38467 (small RAM proof variant) | n/a |

### Synthesis proof
- Yosys command uses the 16-word `mem32_small.sv` proof variant and synthesizes `top_pipe` with `csrs_pipe`, `fetch_pred`, and CSR helpers.
- Result: no errors, no latches, `38467` total cells in the hierarchy.

### Honest limitations
- This is a local Zicsr/trap/timer/xhalt model compatible with the directed tests, ISS, and official UI/UM suites; it is not yet an iCE40 FPGA design, UART, cache, or benchmark SPEC CPU design.
- Formal proof is still model-level pipeline invariants from M2; CSR/trap/timer equivalence is not fully formalized.
- The UM IPC remains low because the current multi-cycle M unit dominates those tests; Zicsr/trap additions did not change official UI/UM totals materially.

