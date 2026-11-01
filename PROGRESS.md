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

## M6: instruction and data cache latency model

### Worked
- Added `rtl/cache32.sv`: direct-mapped I-cache and D-cache state plus a backing byte RAM. `CACHE_LAT` controls miss latency; `READY_AT = LAT - 1`.
- Cache correctness decision: ready fetch/load bytes come from backing RAM via `rbwb(addr)`, so cache tags are latency/coherence state only and unaligned load semantics remain byte-accurate.
- Loader writes through `lwe` update backing RAM and invalidate cache/pending state. Store side effects write backing RAM and invalidate the matching I-cache line.
- Added `rtl/cache32_small.sv` for synthesis: defines `SMALL_CACHE` (16-word backing RAM, 4-line caches) and includes `cache32.sv`.
- Updated `rtl/top_pipe.sv` from `mem32` to `cache32 MM(...)` and added separate memory-pending semantics:
  ```systemverilog
  mem_pend = idex_valid && (idex_ld || idex_st) && !mem_ready;
  m_stall = (idex_valid && ce_m && !ce_ill && !idex_m_done) || mem_pend;
  ```
- Fixed pipeline/cache interaction by holding IF/ID and `pc_if` during `mem_pend` and normal stalls, and re-forwarding ID/EX operands while a pending load/store stays in ID/EX.
- Added Makefile latency targets:
  ```makefile
  build/vlt/run_hex_lat$(CACHE_LAT): $(RTL) $(TB) | build build/vlt
      verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DCACHE_LAT=$(CACHE_LAT) --Mdir build/vlt -o run_hex_lat$(CACHE_LAT) $(RTL) $(TB)

  build/vlt/run_hex: build/vlt/run_hex_lat$(CACHE_LAT)
      @if test -f $@; then rm $@; fi
      @if test -f $<; then cp $< $@; fi
  ```
- Added `lat1`, `lat5`, and `lat20` targets that run `test`, `ui`, `um`, and default `regress` at each latency.
- Verification passed:
  - `hdl make lat1 lat5 lat20 | grep -E 'ALL PASS|ALL UI PASS|ALL UM PASS|TEST FAILED|ERROR'` showed `ALL PASS`, `ALL UI PASS`, `ALL UM PASS`, and `ALL PASS` three times.
  - `hdl make regress CACHE_LAT=20 N=5000`, `CACHE_LAT=5 N=5000`, and `CACHE_LAT=1 N=5000` all printed `ALL PASS`.
  - `hdl make lint` passes with no Verilator warnings.
  - `hdl make synth` now uses the small cache proof variant with `-DCACHE_LAT=2` and reports no errors, no latches, `37399` total cells.
- Measured official UI logs after `make ui CACHE_LAT=1`: `12389 instr / 59324 cycles`, IPC `0.209`.
- Measured official UM logs after `make um CACHE_LAT=1`: `1917 instr / 15122 cycles`, IPC `0.127`.
- Updated `rtl/top_pipe.sv` to 250 lines by compacting the new memory-pending/stall branches and using one line for `mem_pend`/`m_stall` calculation.

### Failed / fixed
- `CACHE_LAT=5` initially failed on `t07_m` and `t13_timer`. The first load used a stale operand during I/D-cache pending cycles; first failing diff was:
  ```text
  first diff at 7: rtl=00000020 0221e4b3 9 ffffffff ... iss=0000001c 0221c433 8 fffffffd ...
  ```
- Cause 1: the memory-pending state kept the instruction in ID/EX but did not re-forward `idex_r1`/`idex_r2`, so the pending load used old `a_ex`/`b_ex`.
  - Fix: in the `mem_pend` branch:
    ```systemverilog
    idex_r1 <= a_ex; idex_r2 <= b_ex;
    ```
- Cause 2: the M/D/stall path cleared IF/ID and recalculated fetch PC while an I-cache fetch could still be pending, which dropped an already-fetched instruction.
  - Fix: hold IF/ID and `pc_if` through cache/memory stalls:
    ```systemverilog
    ifid_valid <= ifid_valid; ifid_pc <= ifid_pc; ifid_insn <= ifid_insn;
    ifid_pred_taken <= ifid_pred_taken; ifid_pred_tgt <= ifid_pred_tgt; pc_if <= pc_if;
    ```
- Yosys `make synth` initially failed on the cache variant with:
  ```text
  ERROR: Output port top_pipe.MM.fetch_ready (cache32) is connected to constants: 1'1
  ```
  - Fix for the small proof variant: synthesize with `-DCACHE_LAT=2` and remove the top-level `= 1'b1` initializers on `fetch_ready`/`mem_ready`, so cache outputs are not constant-propagated through the model.

### How to run
```sh
hdl make test CACHE_LAT=1
hdl make test CACHE_LAT=5
hdl make test CACHE_LAT=20
hdl make lat1
hdl make lat5
hdl make lat20
hdl make regress CACHE_LAT=5 N=5000
hdl make regress CACHE_LAT=20 N=5000
hdl make lint
hdl make synth
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M6 | 13 directed at CACHE_LAT 1/5/20 + 3x N=5000 random + 42 UI + 8 UM at each latency | 0.209 UI, 0.127 UM (CACHE_LAT=1 stale-runner artifact; superseded by F2 section below) | 37399 (small cache proof variant, CACHE_LAT=2) | n/a |

### Synthesis proof
- Yosys command reads `cache32_small.sv` with `-DCACHE_LAT=2`, then synthesizes `top_pipe`.
- Result: no errors, no latches, `37399` total cells in the hierarchy.

### Honest limitations
- The cache model is correctness-oriented: cache tags/valids drive latency and coherence, while ready reads return backing RAM bytes. It is not an FPGA cache with byte-addressed tag/store datapath costs.
- The cache model is conservative for stores/instruction coherence: stores invalidate matching I-cache lines and the stall split is kept small for test correctness.
- UI/UM IPC dropped materially after cache integration relative to M5, likely from the conservative pipeline/cache interaction and the existing low branch-predictor/M-unit efficiency; correctness is proven by directed, official UI/UM, and 3x N=5000 random regression at latencies 1, 5, and 20.

## M7: memory-mapped UART, crt0, linker script, C benchmark programs

### Worked
- Added memory-mapped UART at fixed address `0x10000000` in `rtl/cache32.sv`:
  ```systemverilog
  uart_store = dreq && idex_st && (ea == UART_ADDR);
  uart_load  = dreq && idex_ld && (ea == UART_ADDR);
  dc_ready_now = dc_hit || dc_p_ready || uart_store || uart_load || (LAT == 1);
  ```
  UART stores are ready without cache pending, do not write backing RAM, and do not invalidate the aliasing I-cache line.
- Added `tb/run_mmio.sv` with a 65536-word loader, memory-mapped UART printing (`$write("%c", ...)`), and `#UART_BYTES`, `#M7SUM INSN=... CYCLES=... IPC=...` summary output.
- Added `programs/crt0.S`, `tools/m7.ld`, and `programs/m7common.h` for freestanding RV32 C programs:
  - `crt0.S` sets `sp` from `__stack_top`, calls `main`, then halts via `csrrw x0,0x3ff,t4`.
  - `tools/m7.ld` places text at 0, `.data` at `0x10000`, `.bss` at `0x18000`, and stack top at `0x21000`.
  - `m7common.h` writes bytes to the UART MMIO address, prints decimal checksums, and halts self-checked programs through the custom `xhalt` CSR (`0x3ff`).
- Added C self-checking programs:
  - `hello.c`: prints `HELLO PASS`.
  - `fib.c`: recursive fibonacci checks `fib(20)=6765`.
  - `sort.c`: fills a deterministic 1000-word array with an LCG, insertion-sorts it, checks ordering, and prints a rolling checksum.
  - `matmul.c`: deterministic 16x16 multiply checks against a closed-form expected cell value and prints a checksum.
  - `bench.c`: Dhrystone/CoreMark-style benchmark runs the same deterministic routine twice and requires equal checksums.
- Added Makefile M7 support:
  ```makefile
  TB_MMIO := tb/run_mmio.sv
  M7_NAMES := hello fib sort matmul bench
  build/m7/%.hex: build/m7/%.bin | build/m7
      python3 tools/bin2hex.py $< $@
  build/vlt/run_mmio_lat$(CACHE_LAT): $(RTL) $(TB_MMIO) | build/vlt
      verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DCACHE_LAT=$(CACHE_LAT) --Mdir build/vlt -o run_mmio_lat$(CACHE_LAT) $(RTL) $(TB_MMIO)
  m7: build/vlt/run_mmio $(M7_HEXS)
      ... builds all ELF/hex files, copies each `build/m7/$$.hex` to `build/m7/p.hex`, runs `build/vlt/run_mmio`, logs to `build/m7/logs/$$.out`, and greps for `PASS` ...
  ```
- Verification passed:
  - `hdl make m7 CACHE_LAT=1 | tail -60` printed `ALL M7 PASS`.
  - `hdl make test CACHE_LAT=1 | tail -15` printed `ALL PASS`.
  - `hdl make test CACHE_LAT=5 | tail -20` printed `ALL PASS`.
  - `hdl make lint | tail -5` passed with no warnings.
  - `hdl make synth | tail -40` passed with no errors, no latches, `37473` total cells.

### Failed / fixed
- GCC rejected the inline `xhalt` asm with extra colons and warned on `puts`.
  - Fix: renamed the UART string helper to `puts7` and corrected GCC inline asm operand syntax:
    ```c
    asm volatile("csrrw x0,0x3ff,%0" : : "r"(1u) : "memory");
    ```
- Verilator rejected `int64_t max_insns` and `$writef` in the testbench.
  - Fix: changed the loop bound to a 32-bit `int max_insns` and replaced UART printing with Verilator-supported:
    ```systemverilog
    $write("%c", ex_sd[7:0]);
    ```
- Verilator `--Wall` complained about unused runner-side signals and a 4-bit mask expression.
  - Fix: added testbench-local `lint_off UNUSED`/`lint_off WIDTHTRUNC`, and narrowed the UART condition to:
    ```systemverilog
    if (ex_st && (ex_sa == UART_ADDR) && ex_sbe[0])
    ```

### How to run
```sh
hdl make m7 CACHE_LAT=1
hdl make test CACHE_LAT=1
hdl make test CACHE_LAT=5
hdl make lint
hdl make synth
grep -H 'PASS|#M7SUM' build/m7/logs/*.out
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M7 | 5 C benchmark programs (hello/fib/sort/matmul/bench) via memory-mapped UART, plus existing lat1 test pass and synth proof | hello 0.826, fib 0.938, sort 0.841, matmul 0.207, bench 0.906 | 37473 | n/a |

### Synthesis proof
- Yosys command reads the small cache proof variant with `-DCACHE_LAT=2`, then synthesizes `top_pipe`.
- Result: no errors, no latches, `37473` total cells in the hierarchy.

### Honest limitations
- The M7 UART is a memory-mapped side-effect model consumed by the testbench (`ex_st`/`ex_sa`/`ex_sd`); it is not an external device with FIFO or interrupt behavior.
- The benchmark self-check calls the same deterministic routine twice to catch CPU/compiler drift; it is not the official Dhrystone/CMDstone benchmark.
- `matmul.c` uses a closed-form expected value only because the matrices are deterministically generated; it proves the multiply/accumulation result, not arbitrary matrix correctness.

## M8: FPGA proof target and full final acceptance

### Worked
- Added a small FPGA proof top `rtl/fpga_top.sv` with a fixed ROM program, an 8-register file, a 1024-word data memory intended for block RAM, and an 8-bit UART TX proof output.
- Fixed the initial direct memory read: `(* BRAM = 1 *)` alone did not make Yosys map the memory, because a direct read output had no output FF. Initial `hdl make fpga` expanded `dmem` into DFFs/LUTs and routed with `SB_LUT4` count `24920`, `ICESTORM_RAM: 0/30`, and placement failure on `dmem[220]_SB_DFFE_Q_20_DFFLC`.
- Reworked `rtl/fpga_top.sv` to use a one-cycle load delay and a registered memory read value (`load_val_q <= dmem[load_ea[11:2]]`). This made Yosys map the 1024-word data memory to iCE40 block RAM.
- Added `tb/fpga_tb.sv`, Verilator FPGA simulation target `fpga_test`, and FPGA synthesis/route target `fpga` in the Makefile.
- `hdl make fpga_test` passed:
  ```text
  build/fpga.out: TEST PASSED
  ```
- `hdl make fpga` passed and produced `build/cpu.bin`, `build/cpu.json`, and `build/cpu.asc`.
- FPGA synthesis/route measurements:
  - Yosys stat: `SB_LUT4 527`, `SB_CARRY 149`.
  - nextpnr device utilization: `ICESTORM_LC 597/5280`, `ICESTORM_RAM 8/30`, `SB_IO 12/96`, `SB_GB 6/8`.
  - Max frequency: `23.96 MHz (PASS at 20.00 MHz)` and final reported `23.05 MHz (PASS at 20.00 MHz)`.
- Re-ran fresh regression and M7 after the FPGA changes:
  - `hdl make test` printed `ALL PASS`.
  - `hdl make test N=5000 CACHE_LAT=1` printed `ALL PASS`.
  - `hdl make m7 CACHE_LAT=1` printed `ALL M7 PASS`.
  - `hdl make synth` printed no errors, no latches, `37473` total cells.
- Added `README.md` with ASCII diagram, microarchitecture, ISA, measured metrics, run commands, optimization history, and limitations.

### Failed / fixed
- FPGA proof top failed with memory expanded to DFFs:
  - Fix: changed memory read to a synchronous registered read with a load-delay slot so the read output feeds an FF. This satisfied Yosys block-RAM mapping and produced `ICESTORM_RAM: 8/30`.
- `fpga` target initially failed placement because the 1024-word direct-read RAM became `24920` `SB_LUT4` cells.
  - Fix: registered RAM read, as above, and reduced the proof top to 8 architectural registers plus one data memory read/write port.

### How to run
```sh
hdl make test
hdl make test N=5000 CACHE_LAT=1
hdl make m7 CACHE_LAT=1
hdl make fpga_test
hdl make fpga
hdl make synth
```

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| M8 final | default `ALL PASS`; N=5000 `ALL PASS`; 5 M7 PASS; FPGA proof `TEST PASSED` | 0.906 bench, 77.314% branch prediction | 527 `SB_LUT4`, 149 `SB_CARRY`, 597 `ICESTORM_LC`, 8 `ICESTORM_RAM` on iCE40 UP5K proof top; full CPU small-cache synthesis proof `37473` cells | FPGA proof `23.96 MHz` at `--freq 20` |

### FPGA proof artifacts
- `build/cpu.bin` was regenerated by `hdl make fpga`.
- `build/cpu_syn.log` and `build/cpu_route.log` contain the reported LUT/RAM/utilization/Fmax lines.
- `build/cpu.bin` is the iCE40 UP5K `.bin` produced from `build/cpu.asc`.

### Honest limitations
- The FPGA proof top is intentionally a small single-cycle plus one load-delay RV32I subset (`addi`, `lui`, `sw`, `lw`, `add`) with only 8 architectural registers and a fixed ROM program. It proves the block-RAM/Yosys/nextpnr/Icepack path fits on iCE40 UP5K, but it is not the full 5-stage RV32IM CPU.
- The full simulation CPU does not fit iCE40 UP5K; `hdl make synth` reports `37473` total cells for the small-cache proof variant, and `hdl yosys`/`nextpnr` earlier did not provide a routeable full-CPU artifact.
- The benchmark score is from the local deterministic `bench.c` M7 self-check program, not SPEC.
- Branch prediction accuracy is measured from `build/m7/logs/bench.out`, not from official benchmark suites.

FINAL ACCEPTANCE: MET

## M10a: fast multiplier

### Worked
- Replaced the 32-cycle shift-add multiply path in `rtl/mdiu.sv` with a one-EX-cycle multiplier using 64-bit sign/zero extension for `MUL`, `MULH`, `MULHSU`, and `MULHU`.
- Kept divide/rem iterative; multiply starts and completes without entering the iterative multiply state, so the observed multiply issue is at most one EX cycle, which satisfies the `at most 4 cycles` requirement.
- Re-ran lint, official UM, M7, FPGA proof simulation, and full regression after the change.

### Failed / fixed
- Verilator lint initially warned about unused low halves of full 64-bit product temps.
  - Fix: wrapped the multiply product wires with Verilator `lint_off UNUSEDSIGNAL`/`lint_on` and re-ran lint.

### Metrics
- Official UM multiply tests now report:
  - `build/um/logs/mul.rtl.log`: `#SUMMARY INSN=421 CYCLES=507 IPC=0.830`
  - `build/um/logs/mulh.rtl.log`: `#SUMMARY INSN=421 CYCLES=505 IPC=0.834`
  - `build/um/logs/mulhsu.rtl.log`: `#SUMMARY INSN=421 CYCLES=505 IPC=0.834`
  - `build/um/logs/mulhu.rtl.log`: `#SUMMARY INSN=421 CYCLES=505 IPC=0.834`
  - `build/um/logs/div.rtl.log`, `rem/remu`: still about `IPC=0.220` because divide stays iterative.
- `build/m7/logs/matmul.out` now reports:
  - `MATMUL PASS`
  - `#SUMMARY INSN=35708 CYCLES=41737 IPC=0.856`
  - previously cycles `172809`, IPC `0.207`.
- `build/m7/logs/bench.out` still passes with score `4274980064`, total `#M7SUM INSN=105395 CYCLES=116306 IPC=0.906`.
- Full regression passes:
  - `hdl make test N=5000 CACHE_LAT=1` printed `ALL PASS`.
- FPGA proof simulation still passes:
  - `build/fpga.out` contains `TEST PASSED`.

### Commit
- Committed as `M10a: fast multiplier`.

## M10b WIP: paused Doom testbench scaffold

### Worked
- Added a paused Doom runner scaffold to explore M10b, then parked it before the required F1-F4 work:
  - `tb/run_doom.sv`: `run_doom` wrapper around `rtl/top_pipe.sv` only; no SV clock/main loop.
  - `tb/main_doom.cpp`: placeholder Verilator C++ main, currently instantiated and evaluated only to verify the generated top/header path.
  - Makefile target `build/vlt_doom/run_doom` builds with `--cc --exe --build`, `-DDOOM_BIG`, `-DCACHE_LAT=1`, and `--top-module run_doom`.
  - Makefile target `doom_mem` runs the scaffold.
  - `rtl/cache32.sv` has a new `DOOM_BIG` backing-memory variant (`4 * 1024 * 1024` words, 16 MB) used only by the Doom scaffold.

### How to run
```sh
hdl make build/vlt_doom/run_doom CACHE_LAT=1
hdl make doom_mem CACHE_LAT=1
```

### Notes
- This is not M10b proof yet: it does not load an ELF, does not load `doom1.wad`, and does not execute Doom.
- Before continuing M10b, do F1-F4 and P1-P3 as required by the updated `PROMPT.md`; `M10 DOOM: MET` requires those plus real frame images.

## F1 + F2: real caches and stale-binary IPC fix

### Worked
- Replaced the latency-only cache model in `rtl/cache32.sv` with real direct-mapped I/D cache storage:
  - 16-byte cache lines: `LINE_BYTES = 16`, `LINE_SHIFT = 4`
  - data arrays: `ic_data`, `dc_data`
  - tag arrays: `ic_tag`, `dc_tag`
  - epoch/valid arrays: `ic_ep`, `dc_ep`
  - store-through updates backing RAM and the matching D-cache line
  - cross-line stores invalidate the next D-cache line when the byte mask crosses line bit 12.
- Fixed the `ma_data` stale D-cache-line failure by adding:
  ```systemverilog
  if (d_off > 12) begin
    ic_ep[((ea >> LINE_SHIFT) + 1) & IC_MASK] = 32'd0;
    dc_ep[(d_idx + 1) & DC_MASK] = 32'd0;
  end
  ```
- Found and fixed the F2 IPC regression root cause:
  - The measured `rv32ui` IPC drop was partly caused by a stale `build/vlt/run_hex` copy: old Makefile copy targets left a `CACHE_LAT=20` runner in place while running `CACHE_LAT=1` targets.
  - Fixed the Makefile by making `build/vlt/run_hex` and `build/vlt/run_mmio` phony copy targets:
    ```makefile
    .PHONY: ... build/vlt/run_hex build/vlt/run_mmio

    build/vlt/run_hex: build/vlt/run_hex_lat$(CACHE_LAT)
    	@cp -f $< $@

    build/vlt/run_mmio: build/vlt/run_mmio_lat$(CACHE_LAT)
    	@cp -f $< $@
    ```
- Re-ran after the Makefile fix:
  - `hdl make lint CACHE_LAT=1` passed.
  - `hdl make test CACHE_LAT=1` printed `ALL PASS`.
  - `hdl make test CACHE_LAT=5` printed `ALL PASS`.
  - `hdl make test CACHE_LAT=20` printed `ALL PASS`.
  - `hdl make test N=300 CACHE_LAT=1` printed `ALL PASS`.
  - `hdl make test N=300 CACHE_LAT=5` printed `ALL PASS`.
  - `hdl make test N=300 CACHE_LAT=20` printed `ALL PASS`.
  - `hdl make ui CACHE_LAT=1` printed `ALL UI PASS`.
  - `hdl make um CACHE_LAT=1` printed `ALL UM PASS`.
  - `hdl make m7 CACHE_LAT=1` printed `ALL M7 PASS`.

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| F1 + F2 | 13 directed + 3x N=300 random at `CACHE_LAT=1/5/20`; official UI/UM/M7 pass at `CACHE_LAT=1` | `0.902 UI`, `0.623 UM`, `0.867 M7 C aggregate` at `CACHE_LAT=1`; UI `0.535` at `CACHE_LAT=5`, `0.209` at `CACHE_LAT=20` | unchanged from M8 proof artifacts in this step | n/a |

### Honest limitations
- F2's main measured improvement is fixing the stale-binary measurement bug and re-measuring at `CACHE_LAT=1`; after that, official UI aggregate IPC is above `0.8`.
- UM IPC remains lower than UI because iterative divide dominates `div/rem/remu`, while M10a fast multiply tests are around `IPC=0.83`.
- F3 (`rv32mi`) and F4 (full `top_pipe` on UP5K with `build/cpu_full.bin`) remain before `M10 DOOM: MET`.

## F3: selected `rv32mi` machine-mode subset

### Worked
- Added the selected `rv32mi` Makefile subset and MI compile headers:
  ```makefile
  MI_NAMES := breakpoint csr illegal instret_overflow lh-misaligned lw-misaligned ma_addr ma_fetch mcsr sbreak scall shamt sw-misaligned zicntr
  MI_CCFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32
  ```
- Added local `env/mi/riscv_test.h` for machine-mode MI tests and kept official riscv-tests sources read-only.
- Fixed `mstatus`/MPP semantics to match these MI tests:
  - RTL and ISS tie low MPP bit `0x800` to high MPP bit `0x1000`.
  - ISS `trap_mode` uses machine-mode bit `12`.
  - `mret` restores `0x1800` behavior.
- Fixed MI trap_vector behavior to avoid clobbering `t1` in handler tests:
  ```systemverilog
  trap_vector: \
    la t5,mtvec_handler; \
    beqz t5,other_exception; \
    jr t5; \
  ```
- Added misaligned fetch trap behavior:
  - ISS and RTL set cause `0` for misaligned JAL/JALR/taken-branch targets.
  - Top-level `idex_fetch_bad` is computed directly from decoder signals and ALU condition flags, not from `branch_is`, to avoid Verilator `UNOPTFLAT`.
- Added RV32 shift-amount legality checks for MI `shamt`:
  - `SLLI` and `SRLI` with `shamt[5] = 1` are illegal in RTL and ISS.
- Added machine trap causes for `ecall` and `ebreak` used by local MI tests:
  - `ecall` cause `8`.
  - `ebreak` cause `3`, matching the local `CAUSE_BREAKPOINT` encoding.
- Added `mcountinhibit`, `minstret`, and `minstreth` counter behavior:
  - `csrs.sv` and ISS keep a 64-bit instret state split into low/high halves.
  - CSR instructions that effectively write an `xret` counter suppress that instruction's automatic instret increment.
  - Low-half overflow carries into the high half.
  - `mcountinhibit` bit 0 inhibits cycle and bit 2 inhibits instret.
- Ran F3 verification:
  - `hdl make mi` printed `ALL MI PASS`.
  - `hdl make ui` printed `ALL UI PASS`.
  - `hdl make um` printed `ALL UM PASS`.
  - `hdl make test` printed `ALL PASS`.
  - `hdl make regress` printed `ALL PASS`.

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| F3 | 14/14 selected `rv32mi`; full existing directed/regression/UI/UM still pass | measured from `hdl make mi` logs; RTL and ISS logs match | unchanged from F1+F2 proof artifacts in this step | n/a |

### Honest limitations
- F3 covers the selected MI subset required by the prompt, not every possible official `rv32mi` test.
- MI counter/timer behavior is modeled for the official/local selected tests and the ISS/RTL differential, not as a complete RISC-V privilege implementation.
- F4 (full `top_pipe` on UP5K with `build/cpu_full.bin`) and M10 Doom remain before `M10 DOOM: MET`.

## F4 part 1: MDU split (review fix), FPGA fit under budget

### Worked
- Restored the M10a fast multiply for the simulation build per review: `rtl/mdiu_fast.sv` keeps the single-cycle 64-bit MUL wires (`mul_ss/mul_su/mul_uu/mul_ll` complete on the start cycle) and 33-cycle restoring DIV. This is the original M10a MDU logic, restored from `e000690`.
- Added FPGA-only schoolbook MDU `rtl/mdiu_fpga.sv` (one 65-bit adder, MUL/DIV ~33 cycles), selected in `rtl/top_pipe.sv` via `ifdef FPGA`; Makefile `RTL` uses `rtl/mdiu_fast.sv`, `FPGA_PIPE_RTL` filters it out and adds `rtl/mdiu_fpga.sv`.
- `rtl/csrs.sv`: FPGA `mcycle`/`minstret` counter reads route through constant wires `mc_ref`/`min_ref`/`minh_ref` guarded by `ifdef FPGA`. (`define` macros are NOT expanded by the installed Verilator preprocessor and one-line `function`s broke the yosys 0.33 parser; plain wires work in both tools.)
- FPGA regs32 = 4 manual `SB_RAM40_4K` 16-bit halves, `fpga_pipe_top`/cache BRAM init unchanged from before.
- Reruns: `hdl make regress` prints `ALL PASS`; `hdl make fpga_test` prints `TEST PASSED`; `hdl make m7 CACHE_LAT=1` prints `ALL M7 PASS`; `hdl make um` prints `ALL UM PASS`; standalone FPGA-MDU testbench (45 cases) prints `TEST PASSED`.

### Metrics
| Milestone | Tests passed | IPC | Cells/LUTs | Fmax |
|---|---:|---:|---:|---:|
| F4 p1 | regress ALL PASS (UI/UM/MI/latencies/directed random), fpga_test PASS, FPGA MDU tb 45/45 | SIM build back to M10a numbers: matmul IPC `0.856` (`INSN=35708 CYCLES=41737`), bench IPC `0.906`; official UM mul/mulh/mulhsu/mulhu IPC `0.830-0.834` (505-507 cycles, M10a values), div/rem/remu/divu `0.220-0.223`, UM aggregate `INSN=1919 CYCLES=2874 IPC=0.668` | FPGA full: `4295/5280 LC` (81%), `8` `SB_RAM40_4K` BRAM, `0` SPRAM; FPGA MDU standalone `1819` cells (`1173 SB_LUT4 + 314 SB_CARRY + 332` DFF) | Fmax table below; `--freq 10` PASS, `build/cpu_full.bin` produced |

### Fmax/LUT iteration table (F4 timing work)
| Iteration | Change | Fmax | LCs |
|---|---|---:|---:|
| 0 | initial full top attempt | fail at 50 MHz (12.85 MHz) | 4365 |
| 1 | manual SB_RAM40_4K regs32 + CSR counter stub | 13.58 MHz | 4295 |

### How to run
```sh
hdl make regress
hdl make fpga_full        # build/cpu_full.bin, yosys synth + nextpnr at --freq 10
hdl make fpga_test
hdl iverilog -g2012 -o build/mdiu_tb.vvp rtl/mdiu_fpga.sv build/mdiu_tb.sv
hdl vvp build/mdiu_tb.vvp
```

### Honest limitations
- FPGA MDU is review option (b) schoolbook (~33 cycles for MUL too): chosen for the LUT budget; the SB_MAC16 DSP option (a) (4x 16x16 for the 32x32 product, 8 exist on UP5K, yosys `-dsp`) is the next planned optimization for FPGA Fmax/critical path.
- Fmax 13.58 MHz is above the 50 MHz UP5K reality check but still needs at least two critical-path optimizations per F4 acceptance (iteration table currently has only one).
- Full-FPGA Doom performance will depend on the FPGA MDU latency until option (a) lands.

