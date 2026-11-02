# Review instructions (independent milestone review of the RISC-V CPU)

Project (builder's, READ-ONLY for you): PROJECT_DIR
Commit to review: COMMIT_ID ("COMMIT_SUBJECT")
Your clone: REVIEWS_DIR/clone-COMMIT_SHORT  (create it with: git clone -q PROJECT_DIR <clone>; git -C <clone> checkout -q COMMIT_ID)
Your report: REVIEWS_DIR/rv32cpu-COMMIT_SHORT.md

What the CPU is supposed to be: read PROMPT.md in your clone (the specification and milestones). The builder's
PROGRESS.md and commit messages are CLAIMS. Your job is to check them, not to repeat them.

## 1. Mandatory scripted checks (run each, record the exact command and the key output line)
1. Fresh clone builds and the directed tests pass: `hdl make test` (also with CACHE_LAT=5).
2. Official tests: `hdl make ui`, `hdl make um`, and `hdl make mi` if the target exists. Open 2 logs per suite and
   confirm the test really ends with its pass signal, not just a summary line.
3. Random differential tests: `hdl make regress N=500` (at least).
4. C programs: `hdl make m7 CACHE_LAT=1`; confirm each program prints its PASS line.
5. No hard-coded absolute paths: search rtl/ tb/ tools/ programs/ doom/ Makefile for `/home/`.
6. Metrics honesty: for every number in the newest METRICS table / milestone section of PROGRESS.md, find the tool
   output that produced it in your own run, or mark it "not reproduced".
7. Simulation build vs FPGA build: the simulation build must use the fast multiplier (mdiu_fast or equivalent,
   MUL <= 4 cycles: check matmul IPC is about 0.85, not about 0.2).
8. If the commit touches the FPGA build: the FPGA top must instantiate `top_pipe` (the real CPU, not a toy CPU);
   search the FPGA-only code for constant stubs (e.g. `assign <counter> = 32'h0` under `ifdef FPGA`); if you can do
   it within the memory budget, rerun the FPGA build target and compare LC/BRAM/DSP/Fmax with the claim.
9. Optimization claims: an "optimization round" must change RTL. A nextpnr seed/budget change does not count.
10. Finish markers: `M10 DOOM: MET` (or other done markers) may only appear as a line of its own if really done.

## 2. Known failure kinds this builder has produced before (look for these specifically)
latches instead of flip-flops; RV64 compiler flags instead of rv32; hard-coded /home paths; guessed metrics written
as measured; a toy design substituted for the real one; a fast unit silently replaced by a slow one in all builds;
features stubbed to constants to make something fit; seed changes called optimization; done markers written into
notes; tests edited or weakened to pass.

## 3. Code reading (after the scripted checks)
Read `git diff <previous milestone commit>..COMMIT_ID` for rtl/, tb/, Makefile. Look for weakened tests, removed
checks, `ifdef` blocks that change behaviour between builds, constants replacing logic, and anything that makes a
test pass without making the CPU correct. Report file:line for each finding.

## 4. Report format (write it to the report path above)
- Header: commit, date, verdict (PASS / PASS WITH ISSUES / FAIL).
- Table: check number, command, result (✅/❌/⚠️), evidence (key output line).
- Findings: each with severity (high/medium/low), file:line, what is wrong, why it matters.
- "Claims not reproduced": list.
- "Fix list for the builder": short, concrete, numbered.
Keep it factual and short. Then delete your clone directory, and end your reply with `TASK COMPLETE`.
