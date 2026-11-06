RTL := rtl/top_pipe.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mdiu_fast.sv rtl/cache32.sv rtl/regs32.sv rtl/btb.sv rtl/ldext.sv rtl/branch.sv rtl/store.sv rtl/fwd.sv rtl/ldst.sv rtl/bpif.sv rtl/ifdec.sv rtl/csrs_pipe.sv rtl/fetch_pred.sv rtl/csrs.sv rtl/clint_dev.sv
CACHE_LAT ?= 1
RTL_SINGLE := rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32.sv rtl/regs32.sv
TB  := tb/run_hex.sv
TESTS := t01_basic t02_memory t03_control t04_edge t05_jumps t06_fence t07_m t08_bp t09_csr t10_ecall t11_ebreak t12_illegal t13_timer t14_ldst_stall t15_ld_ld_br t16_mret t17_csr_fwd t18_wfi t19_amo t20_amo_illegal t21_fpga_subw t22_fpga_control t24_fpga_csr_writes t24_priv_trap_m t25_priv_mret_umode t99_branchloop t100_csr_branch_fwd t101_linux_csrrw_clear t102_csr_dest_fwd t103_csr_dest_nop
N ?= 200
CC := riscv64-unknown-elf-gcc
CCFLAGS := -march=rv32im_zicsr -mabi=ilp32
UI_CCFLAGS := -march=rv32i_zicsr_zifencei -mabi=ilp32
OC := riscv64-unknown-elf-objcopy

# External inputs (not in the repo). `make deps` clones the two public ones into deps/ at pinned
# revisions; the DOOM shareware WAD you copy to deps/doom1.wad yourself. Any of them can also be
# given on the command line (RVTEST_DIR=..., COREMARK_DIR=..., WAD_SRC=...).
RISCV_TESTS_URL ?= https://github.com/riscv-software-src/riscv-tests.git
RISCV_TESTS_REV ?= 3df703cd52d5f0d8224e3c50bf03c6cb70efff98
COREMARK_URL ?= https://github.com/eembc/coremark.git
COREMARK_REV ?= 1f483d5b8316753a742cbf5590caf5bd0a4e4777
FREERTOS_URL ?= https://github.com/FreeRTOS/FreeRTOS-Kernel.git
ARCHTEST_URL ?= https://github.com/riscv/riscv-arch-test.git
ARCHTEST_REV ?= eb66181dd27ff7847e2c3a010705b13490b0bf75
SAIL_URL ?= https://github.com/riscv/sail-riscv/releases/download/0.16/sail-riscv-Linux-x86_64.tar.gz
FREERTOS_TAG ?= V11.2.0
WAD_SHA1 := 5b2e249b9c5133ec987b3ea77596381dc0d6bc1d
B ?= build
RVTEST_DIR ?= $(firstword $(wildcard deps/riscv-tests/isa ../../downloads/riscv-tests/isa) deps/riscv-tests/isa)
COREMARK_DIR ?= $(firstword $(wildcard deps/coremark ../../downloads/coremark) deps/coremark)
FREERTOS_DIR ?= $(firstword $(wildcard deps/FreeRTOS-Kernel ../../downloads/FreeRTOS-Kernel) deps/FreeRTOS-Kernel)
WAD_SRC ?= $(firstword $(wildcard deps/doom1.wad ../../downloads/doomwad/doom1.wad) deps/doom1.wad)
FPGA_FREQ ?= 12.5
FPGA_SEED ?= 6
# Pinned netlist baseline (review: pass via tool args, not parsed from PROGRESS.md)
FPGA_NETLIST_LUT4 ?= 3292
FPGA_NETLIST_FLOPS ?= 1195
# Pinned netlist for the documented fpga_csrtrap ROM (smaller, but it exercises
# trap CSRs dynamically; see fpga_csrtrap_netlist target below).
FPGA_CSRTRAP_NETLIST_LUT4 ?= 2176
FPGA_CSRTRAP_NETLIST_FLOPS ?= 1020
UI_DIR := $(RVTEST_DIR)/rv32ui
UI_MACROS := $(RVTEST_DIR)/macros/scalar
UM_DIR := $(RVTEST_DIR)/rv32um
UM_MACROS := $(RVTEST_DIR)/macros/scalar
UI_NAMES := $(basename $(notdir $(shell ls $(UI_DIR)/*.S 2>/dev/null)))
UI_HEXES := $(foreach n,$(UI_NAMES),$(B)/ui/$(n).hex)
UI_BINS := $(foreach n,$(UI_NAMES),$(B)/ui/$(n).bin)
UI_LOGS := $(foreach n,$(UI_NAMES),$(B)/ui/logs/$(n).rtl.log $(B)/ui/logs/$(n).iss.log)

UM_CCFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32
UM_NAMES := $(basename $(notdir $(shell ls $(UM_DIR)/*.S 2>/dev/null)))
UM_HEXES := $(foreach n,$(UM_NAMES),$(B)/um/$(n).hex)
UM_BINS := $(foreach n,$(UM_NAMES),$(B)/um/$(n).bin)
UM_LOGS := $(foreach n,$(UM_NAMES),$(B)/um/logs/$(n).rtl.log $(B)/um/logs/$(n).iss.log)

MI_DIR := $(RVTEST_DIR)/rv32mi
MI_CCFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32
MI_MACROS := $(RVTEST_DIR)/macros/scalar
MI_NAMES := breakpoint csr illegal instret_overflow lh-misaligned lw-misaligned ma_addr ma_fetch mcsr sbreak scall sh-misaligned shamt sw-misaligned zicntr
MI_HEXES := $(foreach n,$(MI_NAMES),$(B)/mi/$(n).hex)
MI_BINS := $(foreach n,$(MI_NAMES),$(B)/mi/$(n).bin)
MI_LOGS := $(foreach n,$(MI_NAMES),$(B)/mi/logs/$(n).rtl.log $(B)/mi/logs/$(n).iss.log)
# rv32si (L5): official supervisor-mode sources run with -D__MACHINE_MODE (the
# test bodies map stvec/sepc/sret/... to their machine-mode equivalents, which
# this M+U CPU implements).  dirty.S is skipped: it is SV39-paging (needs the
# Sv32 MMU built at L6) and cannot even assemble for a 32-bit base.
SI_DIR := $(RVTEST_DIR)/rv32si
SI_CCFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32 -D__MACHINE_MODE
SI_MACROS := $(RVTEST_DIR)/macros/scalar
SI_NAMES := csr ma_fetch sbreak scall wfi
SI_HEXES := $(foreach n,$(SI_NAMES),$(B)/si/$(n).hex)
SI_BINS := $(foreach n,$(SI_NAMES),$(B)/si/$(n).bin)
SI_LOGS := $(foreach n,$(SI_NAMES),$(B)/si/logs/$(n).rtl.log $(B)/si/logs/$(n).iss.log)
UA_DIR := $(RVTEST_DIR)/rv32ua
UA_CCFLAGS := -march=rv32im_a_zicsr_zifencei -mabi=ilp32
UA_MACROS := $(RVTEST_DIR)/macros/scalar
UA_NAMES := amoadd_w amoand_w amomaxu_w amomax_w amominu_w amomin_w amoor_w amoswap_w amoxor_w lrsc
UA_HEXES := $(foreach n,$(UA_NAMES),$(B)/ua/$(n).hex)
UA_BINS := $(foreach n,$(UA_NAMES),$(B)/ua/$(n).bin)

.PHONY: deps need_rvtests need_coremark need_wad need_freertos freertos coremark test regress lint clean synth riscof ui um mi mdiu_tb lat1 lat5 lat20 m7 fpga fpga_test fpga_toy fpga_toy_test fpga_mgate fpga_subw_gate fpga_control_gate fpga_csr_gate all_tests fpga_csrtrap_netlist mpp_ret_gate play play_test doom_mem doom_probe doom_elf fpga_full ua si linux linux_sim linux_shell linux_sim_dbg linux_dbg_initrd linux_trace_check linux_ckpt_hash linux_ckpt_save linux_ckpt_restore linux_ckpt_equiv linux_dbg_ckpt $(B)/vlt/run_hex $(B)/vlt/run_mmio
.PRECIOUS: $(B)/%.o $(B)/%.elf $(B)/%.bin $(B)/ui/%.rvo $(B)/ui/%.o $(B)/ui/%.elf $(B)/ui/%.bin $(B)/mi/%.rvo $(B)/mi/%.o $(B)/mi/%.elf $(B)/mi/%.bin
.SECONDARY: $(B)/%.o $(B)/%.elf $(B)/%.bin $(B)/ui/%.rvo $(B)/ui/%.o $(B)/ui/%.elf $(B)/ui/%.bin $(B)/um/%.rvo $(B)/um/%.o $(B)/um/%.elf $(B)/um/%.bin $(B)/mi/%.rvo $(B)/mi/%.o $(B)/mi/%.elf $(B)/mi/%.bin

$(B):
	@mkdir -p $(B)

# --- external inputs ---
deps:
	@mkdir -p deps
	@if [ ! -d deps/riscv-tests ]; then git clone -q $(RISCV_TESTS_URL) deps/riscv-tests && git -C deps/riscv-tests checkout -q $(RISCV_TESTS_REV) && git -C deps/riscv-tests submodule -q update --init env; fi
	@if [ ! -d deps/coremark ]; then git clone -q $(COREMARK_URL) deps/coremark && git -C deps/coremark checkout -q $(COREMARK_REV); fi
	@if [ ! -d deps/FreeRTOS-Kernel ]; then git -c advice.detachedHead=false clone -q --depth 1 --branch $(FREERTOS_TAG) $(FREERTOS_URL) deps/FreeRTOS-Kernel; fi
	@if [ ! -f deps/sail-riscv-0.16-Linux-x86_64.tar.gz ]; then curl -sL -o deps/sail-riscv-0.16-Linux-x86_64.tar.gz $(SAIL_URL); fi
	@if [ ! -d deps/sail-riscv-0.16/sail-riscv-Linux-x86_64 ]; then mkdir -p deps/sail-riscv-0.16 && tar -xzf deps/sail-riscv-0.16-Linux-x86_64.tar.gz -C deps/sail-riscv-0.16 && chmod +x deps/sail-riscv-0.16/sail-riscv-Linux-x86_64/bin/sail_riscv_sim; fi
	@if [ ! -d deps/riscv-arch-test-3.9.1 ]; then \
	  git clone -q --depth 1 --no-checkout $(ARCHTEST_URL) deps/riscv-arch-test-3.9.1 ; \
	  git -C deps/riscv-arch-test-3.9.1 fetch -q origin $(ARCHTEST_REV) --depth 1 ; \
	  git -C deps/riscv-arch-test-3.9.1 sparse-checkout set riscv-test-suite/env riscv-test-suite/rv32i_m/I riscv-test-suite/rv32i_m/M riscv-test-suite/rv32i_m/A riscv-test-suite/rv32i_m/Zifencei riscv-test-suite/rv32i_m/privilege ; \
	  git -C deps/riscv-arch-test-3.9.1 checkout -q $(ARCHTEST_REV) ; \
	 fi
	@echo "deps: riscv-tests $$(git -C deps/riscv-tests rev-parse --short HEAD), coremark $$(git -C deps/coremark rev-parse --short HEAD), FreeRTOS $(FREERTOS_TAG) (pinned; deps/FreeRTOS-Kernel/manifest.yml version)"
	@[ -f deps/doom1.wad ] && echo "deps: doom1.wad present" || echo "deps: for Doom, copy the shareware doom1.wad (v1.9, sha1 $(WAD_SHA1)) to deps/doom1.wad"

need_rvtests:
	@[ -f $(RVTEST_DIR)/rv32ui/addi.S ] || { echo "riscv-tests not found at $(RVTEST_DIR): run 'make deps' or pass RVTEST_DIR=path/to/riscv-tests/isa" >&2; exit 1; }
	@[ -f $(RVTEST_DIR)/../env/encoding.h ] || { echo "riscv-tests env/ submodule missing: git -C $(RVTEST_DIR)/.. submodule update --init env" >&2; exit 1; }

need_coremark:
	@[ -f $(COREMARK_DIR)/core_main.c ] || { echo "CoreMark not found at $(COREMARK_DIR): run 'make deps' or pass COREMARK_DIR=path/to/coremark" >&2; exit 1; }

need_wad:
	@[ -f "$(WAD_SRC)" ] || { echo "doom1.wad not found at $(WAD_SRC): copy the shareware WAD (v1.9) to deps/doom1.wad or pass WAD_SRC=path" >&2; exit 1; }
	@echo "$(WAD_SHA1)  $(WAD_SRC)" | sha1sum -c --quiet - || { echo "$(WAD_SRC) is not the v1.9 shareware doom1.wad (sha1 $(WAD_SHA1))" >&2; exit 1; }

$(B)/ui:
	@mkdir -p $(B)/ui

$(B)/ui/logs:
	@mkdir -p $(B)/ui/logs

$(B)/um:
	@mkdir -p $(B)/um

$(B)/um/logs:
	@mkdir -p $(B)/um/logs

$(B)/vlt:
	@mkdir -p $(B)/vlt

$(B)/mi:
	@mkdir -p $(B)/mi

$(B)/mi/logs:
	@mkdir -p $(B)/mi/logs

$(B)/ua:
	@mkdir -p $(B)/ua

$(B)/ua/logs:
	@mkdir -p $(B)/ua/logs

$(B)/si/logs:
	@mkdir -p $(B)/si/logs

$(B)/%.o: tests/%.S | $(B)
	$(CC) $(CCFLAGS) -c $< -o $(B)/$*.rvo
	$(OC) -O elf32-littleriscv $(B)/$*.rvo $@

# t19: atomics need the A extension (rv32ima) in the assembler march
T19_CCFLAGS := -march=rv32ima_zicsr -mabi=ilp32
$(B)/t19_amo.o: tests/t19_amo.S | $(B)
	$(CC) $(T19_CCFLAGS) -c $< -o $(B)/t19_amo.rvo
	$(OC) -O elf32-littleriscv $(B)/t19_amo.rvo $@

# t20: reserved atomics and MMIO atomic traps need the A extension too
T20_CCFLAGS := -march=rv32ima_zicsr -mabi=ilp32
$(B)/t20_amo_illegal.o: tests/t20_amo_illegal.S | $(B)
	$(CC) $(T20_CCFLAGS) -c $< -o $(B)/t20_amo_illegal.rvo
	$(OC) -O elf32-littleriscv $(B)/t20_amo_illegal.rvo $@

$(B)/t23_mret_mpp.o: tests/t23_mret_mpp.S | $(B)
	$(CC) $(CCFLAGS) -c $< -o $(B)/t23_mret_mpp.rvo
	$(OC) -O elf32-littleriscv $(B)/t23_mret_mpp.rvo $@

$(B)/%.elf: $(B)/%.o tests/link.ld | $(B)
	$(CC) $(CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

$(B)/%.bin: $(B)/%.elf | $(B)
	$(OC) -O binary $< $@

$(B)/%.hex: $(B)/%.bin | $(B)
	python3 tools/bin2hex.py $< $@

$(B)/ui/%.o: $(UI_DIR)/%.S env/riscv_test.h | $(B)/ui
	$(CC) $(UI_CCFLAGS) -c $< -I env -I $(UI_MACROS) -o $(B)/ui/$*.rvo
	$(OC) -O elf32-littleriscv $(B)/ui/$*.rvo $@

$(B)/ui/%.elf: $(B)/ui/%.o tests/link.ld | $(B)/ui
	$(CC) $(UI_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

$(B)/ui/%.bin: $(B)/ui/%.elf | $(B)/ui
	$(OC) -O binary $< $@

$(B)/ui/%.hex: $(B)/ui/%.bin | $(B)/ui
	python3 tools/bin2hex.py $< $@

$(B)/um/%.o: $(UM_DIR)/%.S env/riscv_test.h | $(B)/um
	$(CC) $(UM_CCFLAGS) -c $< -I env -I $(UM_MACROS) -o $(B)/um/$*.rvo
	$(OC) -O elf32-littleriscv $(B)/um/$*.rvo $@

$(B)/um/%.elf: $(B)/um/%.o tests/link.ld | $(B)/um
	$(CC) $(UM_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

$(B)/um/%.bin: $(B)/um/%.elf | $(B)/um
	$(OC) -O binary $< $@

$(B)/um/%.hex: $(B)/um/%.bin | $(B)/um
	python3 tools/bin2hex.py $< $@

$(B)/mi/%.o: $(MI_DIR)/%.S env/mi/riscv_test.h | $(B)/mi
	$(CC) $(MI_CCFLAGS) -c $< -I env/mi -I $(RVTEST_DIR)/../env -I $(MI_MACROS) -o $(B)/mi/$*.rvo
	$(OC) -O elf32-littleriscv $(B)/mi/$*.rvo $@

$(B)/mi/%.elf: $(B)/mi/%.o tests/link.ld | $(B)/mi
	$(CC) $(MI_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

$(B)/mi/%.bin: $(B)/mi/%.elf | $(B)/mi
	$(OC) -O binary $< $@

$(B)/mi/%.hex: $(B)/mi/%.bin | $(B)/mi
	python3 tools/bin2hex.py $< $@

$(B)/si:
	@mkdir -p $(B)/si

$(B)/si/%.o: $(SI_DIR)/%.S env/si/riscv_test.h | $(B)/si
	$(CC) $(SI_CCFLAGS) -c $< -I env/si -I $(RVTEST_DIR)/../env -I $(SI_MACROS) -o $(B)/si/$*.rvo
	$(OC) -O elf32-littleriscv $(B)/si/$*.rvo $@

$(B)/si/%.elf: $(B)/si/%.o tests/link.ld | $(B)/si
	$(CC) $(SI_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

$(B)/si/%.bin: $(B)/si/%.elf | $(B)/si
	$(OC) -O binary $< $@

$(B)/si/%.hex: $(B)/si/%.bin | $(B)/si
	python3 tools/bin2hex.py $< $@

$(B)/ua/%.o: $(UA_DIR)/%.S env/riscv_test.h | $(B)/ua
	$(CC) $(UA_CCFLAGS) -c $< -I env -I $(UA_MACROS) -o $(B)/ua/$*.rvo
	$(OC) -O elf32-littleriscv $(B)/ua/$*.rvo $@

$(B)/ua/%.elf: $(B)/ua/%.o tests/link.ld | $(B)/ua
	$(CC) $(UA_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

$(B)/ua/%.bin: $(B)/ua/%.elf | $(B)/ua
	$(OC) -O binary $< $@

$(B)/ua/%.hex: $(B)/ua/%.bin | $(B)/ua
	python3 tools/bin2hex.py $< $@


$(B)/sim_%.vvp: $(RTL) $(TB) | $(B)
	iverilog -g2012 -Wall -DTBHEX='"$(B)/$*.hex"' -DTOPPIPE -o $(B)/sim_$*.vvp $(RTL) $(TB)

test: $(foreach t,$(TESTS),$(B)/$t.bin $(B)/$t.hex) $(UI_BINS) $(UI_HEXES) $(UM_BINS) $(UM_HEXES) $(B)/vlt/run_hex | need_rvtests $(B)/ui $(B)/ui/logs $(B)/um $(B)/um/logs
	@bad=0; mkdir -p $(B)/rand; \
	for t in $(TESTS); do \
  cp $(B)/$$t.hex $(B)/p.hex; ./$(B)/vlt/run_hex > $(B)/$$t.rtl.log; \
  python3 iss/iss.py --quiet --pass --log $(B)/$$t.iss.log $(B)/$$t.bin > /dev/null || { echo "$$t: ISS pass marker not reached"; bad=$$((bad+1)); }; \
  python3 tools/cmp.py $(B)/$$t.rtl.log $(B)/$$t.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
	 python3 iss/iss.py --quiet --pass $(B)/t16_mret.bin > /dev/null || { echo "t16_mret: mret did not return to mepc"; bad=$$((bad+1)); }; \
	 python3 iss/iss.py --quiet --pass $(B)/t18_wfi.bin > /dev/null || { echo "t18_wfi: self-check branch taken (gp!=1)"; bad=$$((bad+1)); }; \
	 python3 iss/iss.py --quiet --pass $(B)/t19_amo.bin > /dev/null || { echo "t19_amo: atomics self-check branch taken (gp!=1)"; bad=$$((bad+1)); }; \
 	 python3 iss/iss.py --quiet --pass $(B)/t20_amo_illegal.bin > /dev/null || { echo "t20_amo_illegal: illegal/reserved/MMIO atomics self-check branch taken (gp!=1)"; bad=$$((bad+1)); }; \
 	 for t in t99_branchloop t100_csr_branch_fwd t101_linux_csrrw_clear t102_csr_dest_fwd t103_csr_dest_nop; do \
 	 python3 iss/iss.py --quiet --pass $(B)/$$t.bin > /dev/null || { echo "$$t: gp self-check failed (gp!=1)"; bad=$$((bad+1)); }; \
 	 done; \
 	 for n in $(UI_NAMES); do \
	 cp $(B)/ui/$$n.hex $(B)/p.hex; ./$(B)/vlt/run_hex > $(B)/ui/logs/$$n.rtl.log; \
	 python3 iss/iss.py --quiet --pass --log $(B)/ui/logs/$$n.iss.log $(B)/ui/$$n.bin > /dev/null; \
	 python3 tools/cmp.py $(B)/ui/logs/$$n.rtl.log $(B)/ui/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 for n in $(UM_NAMES); do \
	 cp $(B)/um/$$n.hex $(B)/p.hex; ./$(B)/vlt/run_hex > $(B)/um/logs/$$n.rtl.log; \
	 python3 iss/iss.py --quiet --pass --log $(B)/um/logs/$$n.iss.log $(B)/um/$$n.bin > /dev/null; \
	 python3 tools/cmp.py $(B)/um/logs/$$n.rtl.log $(B)/um/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 for i in $(shell seq 1 $(N)); do \
 	 python3 tools/gen.py $$i $(B)/rand/p$$i > /dev/null || bad=$$((bad+1)); cp $(B)/rand/p$$i.hex $(B)/p.hex; ./$(B)/vlt/run_hex > $(B)/rand/$$i.rtl.log; \
	 python3 iss/iss.py --quiet --log $(B)/rand/$$i.iss.log $(B)/rand/p$$i.bin > /dev/null; \
	 python3 tools/cmp.py $(B)/rand/$$i.rtl.log $(B)/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; exit 1; fi

ui: $(UI_BINS) $(UI_HEXES) $(B)/vlt/run_hex | need_rvtests $(B)/ui $(B)/ui/logs
	@bad=0; \
  for n in $(UI_NAMES); do \
    cp $(B)/ui/$$n.hex $(B)/p.hex; \
    ./$(B)/vlt/run_hex > $(B)/ui/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log $(B)/ui/logs/$$n.iss.log $(B)/ui/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py $(B)/ui/logs/$$n.rtl.log $(B)/ui/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UI PASS; else echo "UI TEST FAILED: $$bad errors"; exit 1; fi

$(B)/vlt/run_hex_lat$(CACHE_LAT): $(RTL) $(TB) | $(B) $(B)/vlt
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DTBHEX='"$(B)/p.hex"' -DCACHE_LAT=$(CACHE_LAT) --Mdir $(B)/vlt -o run_hex_lat$(CACHE_LAT) $(RTL) $(TB)

$(B)/vlt/run_hex: $(B)/vlt/run_hex_lat$(CACHE_LAT)
	@cp -f $< $@

um: $(UM_BINS) $(UM_HEXES) $(B)/vlt/run_hex | need_rvtests $(B)/um $(B)/um/logs
	@bad=0; \
  for n in $(UM_NAMES); do \
    cp $(B)/um/$$n.hex $(B)/p.hex; \
    ./$(B)/vlt/run_hex > $(B)/um/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log $(B)/um/logs/$$n.iss.log $(B)/um/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py $(B)/um/logs/$$n.rtl.log $(B)/um/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UM PASS; else echo "UM TEST FAILED: $$bad errors"; exit 1; fi

mi: $(MI_BINS) $(MI_HEXES) $(B)/vlt/run_hex | need_rvtests $(B)/mi $(B)/mi/logs
	@bad=0; \
  for n in $(MI_NAMES); do \
    cp $(B)/mi/$$n.hex $(B)/p.hex; \
    ./$(B)/vlt/run_hex > $(B)/mi/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log $(B)/mi/logs/$$n.iss.log $(B)/mi/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py $(B)/mi/logs/$$n.rtl.log $(B)/mi/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL MI PASS; else echo "MI TEST FAILED: $$bad errors"; exit 1; fi

ua: $(UA_BINS) $(UA_HEXES) $(B)/vlt/run_hex | need_rvtests $(B)/ua $(B)/ua/logs
	@bad=0;   for n in $(UA_NAMES); do     cp $(B)/ua/$$n.hex $(B)/p.hex;     ./$(B)/vlt/run_hex > $(B)/ua/logs/$$n.rtl.log;     python3 iss/iss.py --quiet --pass --log $(B)/ua/logs/$$n.iss.log $(B)/ua/$$n.bin > /dev/null || bad=$$((bad+1));     python3 tools/cmp.py $(B)/ua/logs/$$n.rtl.log $(B)/ua/logs/$$n.iss.log > /dev/null || bad=$$((bad+1));   done;   if [ $$bad -eq 0 ]; then echo ALL UA PASS; else echo "UA TEST FAILED: $$bad errors"; exit 1; fi

si: $(SI_BINS) $(SI_HEXES) $(B)/vlt/run_hex | need_rvtests $(B)/si $(B)/si/logs
	@bad=0; \
  for n in $(SI_NAMES); do \
    cp $(B)/si/$$n.hex $(B)/p.hex; \
    ./$(B)/vlt/run_hex > $(B)/si/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log $(B)/si/logs/$$n.iss.log $(B)/si/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py $(B)/si/logs/$$n.rtl.log $(B)/si/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL SI PASS; else echo "SI TEST FAILED: $$bad errors"; exit 1; fi


regress: $(B)/vlt/run_hex
	@bad=0; mkdir -p $(B)/rand; for i in $(shell seq 1 $(N)); do python3 tools/gen.py $$i $(B)/rand/p$$i > /dev/null || bad=$$((bad+1)); cp $(B)/rand/p$$i.hex $(B)/p.hex; ./$(B)/vlt/run_hex > $(B)/rand/$$i.rtl.log; python3 iss/iss.py --quiet --log $(B)/rand/$$i.iss.log $(B)/rand/p$$i.bin > /dev/null; python3 tools/cmp.py $(B)/rand/$$i.rtl.log $(B)/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; exit 1; fi

TB_MMIO := tb/run_mmio.sv
M7_NAMES := hello fib sort matmul bench
M7_CFLAGS := $(CCFLAGS) -O2 -fno-plt -fno-stack-protector -Iprograms
M7_HEXS := $(foreach n,$(M7_NAMES),$(B)/m7/$(n).hex)

$(B)/m7:
	@mkdir -p $(B)/m7

$(B)/m7/crt0.o: programs/crt0.S | $(B)/m7
	$(CC) $(CCFLAGS) -c $< -o $@

$(B)/m7/%.o: programs/%.c | $(B)/m7
	$(CC) $(M7_CFLAGS) -c $< -o $@

$(B)/m7/%.elf: $(B)/m7/%.o $(B)/m7/crt0.o tools/m7.ld | $(B)/m7
	$(CC) $(M7_CFLAGS) -nostdlib -nostartfiles -Wl,-Ttools/m7.ld -Wl,-m,elf32lriscv -o $@ $(B)/m7/crt0.o $<

$(B)/m7/%.bin: $(B)/m7/%.elf | $(B)/m7
	$(OC) -O binary $< $@

$(B)/m7/%.hex: $(B)/m7/%.bin | $(B)/m7
	python3 tools/bin2hex.py $< $@

$(B)/vlt/run_mmio_lat$(CACHE_LAT): $(RTL) $(TB_MMIO) | $(B)/vlt
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DCACHE_LAT=$(CACHE_LAT) --Mdir $(B)/vlt -o run_mmio_lat$(CACHE_LAT) $(RTL) $(TB_MMIO)

$(B)/vlt/run_mmio: $(B)/vlt/run_mmio_lat$(CACHE_LAT)
	@cp -f $< $@

m7: $(B)/vlt/run_mmio $(M7_HEXS)
	@bad=0; mkdir -p $(B)/m7/logs; for n in $(M7_NAMES); do cp $(B)/m7/$$n.hex $(B)/m7/p.hex; ./$(B)/vlt/run_mmio > $(B)/m7/logs/$$n.out; grep -q PASS $(B)/m7/logs/$$n.out > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL M7 PASS; else echo "M7 TEST FAILED: $$bad errors"; exit 1; fi

# --- CoreMark (EEMBC) on the Doom-configuration CPU (16+16 KB caches, CACHE_LAT=5) ---
# COREMARK_DIR: an upstream checkout of https://github.com/eembc/coremark (port files in bench/coremark).
COREMARK_DIR ?= ../../downloads/coremark
CM_ITER ?= 500
CM_OPT ?= -O2
CM_SRCS := $(addprefix $(COREMARK_DIR)/,core_list_join.c core_main.c core_matrix.c core_state.c core_util.c) \
           bench/coremark/core_portme.c bench/coremark/ee_printf.c bench/coremark/cvt.c
CM_FLAGS := $(CCFLAGS) $(CM_OPT) -DITERATIONS=$(CM_ITER) -DPERFORMANCE_RUN=1 -DFLAGS_STR='"$(CM_OPT)"'

$(B)/bench:
	@mkdir -p $(B)/bench

$(B)/bench/coremark.elf: $(CM_SRCS) bench/coremark/core_portme.h doom/crt0_rv32.S doom/exit_rv.S doom/ld.ld | $(B)/bench
	$(CC) $(CM_FLAGS) -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -I bench/coremark -I $(COREMARK_DIR) -o $@ doom/crt0_rv32.S doom/exit_rv.S $(CM_SRCS)

$(B)/bench/coremark.bin: $(B)/bench/coremark.elf
	$(OC) -O binary $< $@

$(B)/bench/coremark.hex: $(B)/bench/coremark.bin
	python3 tools/bin2hex.py $< $@

$(B)/vlt_bench/run_bench: $(RTL) tb/run_doom.sv tb/bench_main.cpp | $(B)
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast -DDOOM_BIG -DCACHE_LAT=5 -DTOPPIPE --top-module run_doom --Mdir $(B)/vlt_bench -o run_bench $(RTL) tb/run_doom.sv $(CURDIR)/tb/bench_main.cpp
	$(MAKE) -C $(B)/vlt_bench -f Vrun_doom.mk OPT_FAST="-O3" run_bench -j 4

coremark: need_coremark $(B)/vlt_bench/run_bench $(B)/bench/coremark.hex
	@./$(B)/vlt_bench/run_bench $(B)/bench/coremark.hex | tee $(B)/bench/coremark.out
	@python3 tools/coremark_score.py $(B)/bench/coremark.out

# --- FreeRTOS demo on the same CPU configuration as Doom and CoreMark (stock port) ---
RTOS_PORT_DIR := $(FREERTOS_DIR)/portable/GCC/RISC-V
RTOS_CHIP_DIR := $(RTOS_PORT_DIR)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
RTOS_SRCS := $(addprefix $(FREERTOS_DIR)/,tasks.c queue.c list.c timers.c portable/MemMang/heap_4.c) \
             $(RTOS_PORT_DIR)/port.c os/freertos/main.c
RTOS_FLAGS := $(CCFLAGS) -O2 -I os/freertos -I $(RTOS_PORT_DIR) -I $(RTOS_CHIP_DIR) -I $(FREERTOS_DIR)/include
RTOS_ASM_FLAGS := $(CCFLAGS) -O2 -I $(RTOS_PORT_DIR) -I $(RTOS_CHIP_DIR) -I $(FREERTOS_DIR)/include

need_freertos:
	@[ -f $(FREERTOS_DIR)/tasks.c ] || { echo "FreeRTOS not found at $(FREERTOS_DIR): run 'make deps' or pass FREERTOS_DIR=path/to/FreeRTOS-Kernel" >&2; exit 1; }

$(B)/bench/portASM.o: $(RTOS_PORT_DIR)/portASM.S $(RTOS_CHIP_DIR)/freertos_risc_v_chip_specific_extensions.h | $(B)/bench
	$(CC) $(RTOS_ASM_FLAGS) -c $< -o $@

$(B)/bench/freertos.elf: $(RTOS_SRCS) $(B)/bench/portASM.o $(RTOS_PORT_DIR)/portASM.S $(RTOS_PORT_DIR)/portmacro.h $(RTOS_CHIP_DIR)/freertos_risc_v_chip_specific_extensions.h os/freertos/crt0.S os/freertos/FreeRTOSConfig.h doom/exit_rv.S doom/ld.ld | $(B)/bench
	$(CC) $(RTOS_FLAGS) -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -o $@ os/freertos/crt0.S doom/exit_rv.S $(B)/bench/portASM.o $(RTOS_SRCS)

$(B)/bench/freertos.bin: $(B)/bench/freertos.elf
	$(OC) -O binary $< $@

$(B)/bench/freertos.hex: $(B)/bench/freertos.bin
	python3 tools/bin2hex.py $< $@

freertos: need_freertos $(B)/vlt_bench/run_bench $(B)/bench/freertos.hex
	@./$(B)/vlt_bench/run_bench $(B)/bench/freertos.hex 400000000 | tee $(B)/bench/freertos.out
	@grep -q "^FREERTOS PASS" $(B)/bench/freertos.out || { echo "FREERTOS TEST FAILED" >&2; exit 1; }

# --- Linux platform: 64MB RAM, UART 16550 at 0x1000_0000, CLINT at 0x0200_0000 ---
LINUX_KERNEL_BIN ?= ../../build-linux/nommu/images/vmlinux.bin
KERNEL_SHA256 ?= 2bdaf20814e28e45ac315fc7db5cadd079dfeecfe99e9f06691772ee77aaf0bd
LINUX_ROOTFS_BIN ?= ../../build-linux/nommu/images/rootfs.cpio
ROOTFS_SHA256 ?= 6f4a9e7321da671910520379cabf9ef57a2751da01c4965ff7529d21f84a9c9a
BR_ROOT ?= ../../downloads/buildroot-2025.02.19
BR_OUT ?= ../../build-linux/nommu
BR_DEFCONFIG ?= linux/configs/qemu_riscv32_nommu_virt_defconfig
LINUX_CKPT_FILE ?= $(B)/linux_ckpt.bin
LINUX_CKPT_SAVE_CYCLE ?= 85000000
LINUX_CKPT_LATER_CYCLE ?= 90000000
LINUX_CKPT_HASH ?= $(shell sha256sum $(RTL) tb/run_linux.sv tb/run_linux.cpp linux/vmlinux.bin linux/linux.dtb | sha256sum | cut -d' ' -f1)
LINUX_DBG_CYCLES ?= 150000000
LINUX_SHELL_CYCLES ?= 800000000
linux:
	@mkdir -p linux $(B)/linux
$(B)/linux/logs:
	@mkdir -p $@
linux/linux.dtb: rtl/linux.dts linux | $(B)
	@mkdir -p linux
	@dtc -I dts -O dtb -o linux/linux.dtb rtl/linux.dts
linux/vmlinux.bin: linux | $(B)
	@if [ ! -f linux/vmlinux.bin ]; then cp $(LINUX_KERNEL_BIN) linux/vmlinux.bin; fi
linux/rootfs_unfiltered.cpio: linux | $(B)
	@if [ ! -f linux/rootfs_unfiltered.cpio ]; then cp $(LINUX_ROOTFS_BIN) linux/rootfs_unfiltered.cpio; fi
linux/rootfs.cpio: linux/rootfs_unfiltered.cpio linux | $(B)
	@python3 tools/rootfs_drop_network.py linux/rootfs_unfiltered.cpio linux/rootfs.cpio etc/init.d/S40network
linux/linux_initrd.dtb: linux/linux_initrd.dts linux | $(B)
	@mkdir -p linux
	@dtc -I dts -O dtb -o linux/linux_initrd.dtb linux/linux_initrd.dts
linux_rebuild_kernel: linux | $(BR_OUT)
	$(MAKE) -C $(BR_ROOT) O=$(BR_OUT) defconfig BR2_DEFCONFIG=$(CURDIR)/$(BR_DEFCONFIG)
	$(MAKE) -C $(BR_ROOT) O=$(BR_OUT) linux
	@mkdir -p linux $(B)
	@cp $(BR_OUT)/images/vmlinux.bin $(B)/linux_kernel_rebuilt.bin
	@python3 tools/kernel_disable_embedded_initramfs.py $(B)/linux_kernel_rebuilt.bin linux/vmlinux.bin
	@cp $(BR_OUT)/images/rootfs.cpio linux/rootfs_unfiltered.cpio
	@python3 tools/rootfs_drop_network.py linux/rootfs_unfiltered.cpio linux/rootfs.cpio etc/init.d/S40network
	@sha256sum linux/vmlinux.bin linux/rootfs.cpio
	@echo "Expected KERNEL_SHA256=$(KERNEL_SHA256) ROOTFS_SHA256=$(ROOTFS_SHA256)"

linux_pinned_kernel: linux | $(B)
	@mkdir -p linux $(B)
	@python3 tools/git_blob_to_file.py 09a6ad3 $(B)/linux_kernel_blob.bin
	@python3 tools/kernel_disable_embedded_initramfs.py $(B)/linux_kernel_blob.bin linux/vmlinux.bin
	@sha256sum linux/vmlinux.bin
	@echo "Recovered pinned kernel for KERNEL_SHA256=$(KERNEL_SHA256)"

linux_pinned_rootfs: linux | $(B)
	@mkdir -p linux $(B)
	@python3 tools/git_blob_to_file.py HEAD:linux/rootfs.cpio $(B)/linux_rootfs_blob.bin
	@cp $(B)/linux_rootfs_blob.bin linux/rootfs.cpio
	@sha256sum linux/rootfs.cpio
	@echo "Recovered pinned rootfs for ROOTFS_SHA256=$(ROOTFS_SHA256)"

linux/gate.txt: linux/configs/gate-symbols.map linux | $(B)
	@mkdir -p linux
	@python3 tools/linux_gate.py linux/configs/gate-symbols.map linux/gate.txt
$(B)/vlt_linux/run_linux: $(RTL) tb/run_linux.sv tb/run_linux.cpp | linux
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast -DLINUX -DCACHE_LAT=1 --top-module run_linux --Mdir $(B)/vlt_linux -o run_linux $(RTL) tb/run_linux.sv $(CURDIR)/tb/run_linux.cpp
	$(MAKE) -C $(B)/vlt_linux -f Vrun_linux.mk OPT_FAST="-O3" run_linux -j 4

$(B)/vlt_linux_dbg/run_linux: $(RTL) tb/run_linux.sv tb/run_linux.cpp | linux
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast -DLINUX -DCACHE_LAT=1 -DLINUX_DEBUG --top-module run_linux --Mdir $(B)/vlt_linux_dbg -o run_linux $(RTL) tb/run_linux.sv $(CURDIR)/tb/run_linux.cpp
	$(MAKE) -C $(B)/vlt_linux_dbg -f Vrun_linux.mk OPT_FAST="-O3 -DLINUX_DEBUG" run_linux -j 4

linux_sim_dbg: $(B)/vlt_linux_dbg/run_linux | linux linux/linux.dtb linux_pinned_kernel $(B)/linux/logs
	@ok=1; for f in linux/vmlinux.bin linux/linux.dtb; do if [ ! -s $$f ]; then echo "Linux test input missing: $$f"; ok=0; fi; done; if [ $$ok -ne 1 ]; then echo "Recover the pinned kernel with make linux_pinned_kernel, rebuild from the committed Buildroot recipe with make linux_rebuild_kernel, or download linux/vmlinux.bin and linux/linux.dtb from the GitHub Release asset for KERNEL_SHA256 $(KERNEL_SHA256)."; exit 1; fi
	@sha256sum linux/vmlinux.bin | grep -q $(KERNEL_SHA256) || { echo "LINUX DEBUG BOOT TEST FAILED: kernel sha256 mismatch (expected $(KERNEL_SHA256))" >&2; exit 1; }
	@mkdir -p $(B)/linux/logs; ./$(B)/vlt_linux_dbg/run_linux linux/vmlinux.bin linux/linux.dtb 90000000 prompt | tee $(B)/linux/logs/boot_dbg.out

# Independent retire-trace replay checker. Run it after linux_sim_dbg (or after
# linux_dbg_initrd by editing the kernel/dtb inputs/log); it must use the same
# vmlinux.bin, dtb and dtb_addr that produced build/linux/cpu_retire.bin. The
# runner prints the load address as `dtb=xxxxxxxx` in its final #LINUX line.
linux_trace_check: linux_sim_dbg | linux linux/linux.dtb linux_pinned_kernel $(B)/linux/logs
	@mkdir -p $(B)/linux/logs
	@sha256sum linux/vmlinux.bin | grep -q $(KERNEL_SHA256) || { echo "linux_trace_check: kernel sha256 mismatch (expected $(KERNEL_SHA256))" >&2; exit 1; }
	@DTB=`grep -o 'dtb=[0-9a-f]\{8\}' $(B)/linux/logs/boot_dbg.out | tail -n 1 | cut -d= -f 2`; \
	 [ -n "$$DTB" ] || { echo "linux_trace_check: no dtb=xxxxxxxx address found in $(B)/linux/logs/boot_dbg.out" >&2; exit 1; }; \
	 echo "linux_trace_check: using kernel linux/vmlinux.bin, dtb linux/linux.dtb, dtb_addr $$DTB"; \
	 python3 tools/trace_replay_check.py build/linux/cpu_retire.bin linux/vmlinux.bin linux/linux.dtb "$$DTB" 30 | tee $(B)/linux/logs/trace_replay_check.out

linux_sim: $(B)/vlt_linux/run_linux linux/gate.txt | linux linux/linux.dtb linux_pinned_kernel $(B)/linux/logs
	@ok=1; for f in linux/vmlinux.bin linux/linux.dtb; do if [ ! -s $$f ]; then echo "Linux test input missing: $$f"; ok=0; fi; done; if [ $$ok -ne 1 ]; then echo "Recover the pinned kernel with make linux_pinned_kernel or rebuild from the committed Buildroot recipe with make linux_rebuild_kernel; linux/linux.dtb is generated by make linux/linux.dtb."; exit 1; fi
	@sha256sum linux/vmlinux.bin | grep -q $(KERNEL_SHA256) || { echo "LINUX L3 TEST FAILED: kernel sha256 mismatch (expected $(KERNEL_SHA256)); regenerate with make linux_pinned_kernel or make linux_rebuild_kernel" >&2; exit 1; }
	./$(B)/vlt_linux/run_linux linux/vmlinux.bin linux/linux.dtb 6000000 platform | tee $(B)/linux/logs/boot.out
	@grep -q "^#STOP platform" $(B)/linux/logs/boot.out || { echo "LINUX L3 PLATFORM BOOT TEST FAILED" >&2; exit 1; }
	@grep -q "#GATE start_kernel " $(B)/linux/logs/boot.out || { echo "LINUX L3 TEST FAILED: start_kernel not reached" >&2; exit 1; }
	@grep -q "#GATE kernel_init " $(B)/linux/logs/boot.out || { echo "LINUX L3 TEST FAILED: kernel_init not reached" >&2; exit 1; }
	@grep -q "#GATE kernel_init_freeable " $(B)/linux/logs/boot.out || { echo "LINUX L3 TEST FAILED: kernel_init_freeable not reached" >&2; exit 1; }
	@grep -q "#GATE wait_for_initramfs " $(B)/linux/logs/boot.out || { echo "LINUX L3 TEST FAILED: wait_for_initramfs not reached" >&2; exit 1; }
	@grep -q "#GATE run_init_process " $(B)/linux/logs/boot.out || { echo "LINUX L3 TEST FAILED: run_init_process not reached" >&2; exit 1; }
	@grep -q "^#LINUX" $(B)/linux/logs/boot.out || { echo "LINUX L3 TEST FAILED: runner did not finish" >&2; exit 1; }
	@echo "TEST PASSED (L3 platform boot: Linux reaches init_freeable; BusyBox prompt not reached yet)"

linux_shell: $(B)/vlt_linux/run_linux | linux linux/linux_initrd.dtb linux_pinned_kernel linux_pinned_rootfs linux/rootfs.cpio $(B)/linux/logs
	@sha256sum linux/vmlinux.bin | grep -q $(KERNEL_SHA256) || { echo "LINUX SHELL TEST FAILED: kernel sha256 mismatch (expected $(KERNEL_SHA256))" >&2; exit 1; }
	@sha256sum linux/rootfs.cpio | grep -q $(ROOTFS_SHA256) || { echo "LINUX SHELL TEST FAILED: rootfs sha256 mismatch (expected $(ROOTFS_SHA256))" >&2; exit 1; }
	@mkdir -p $(B)/linux/logs; env LINUX_INITRD=linux/rootfs.cpio ./$(B)/vlt_linux/run_linux linux/vmlinux.bin linux/linux_initrd.dtb $(LINUX_SHELL_CYCLES) shell > $(B)/linux/logs/shell.out; sed -n '1,160p' $(B)/linux/logs/shell.out; tail -n 6 $(B)/linux/logs/shell.out; grep -q "#LINUX.*login=1" $(B)/linux/logs/shell.out || { echo "LINUX SHELL TEST FAILED: login prompt not seen" >&2; exit 1; }; grep -q "#LINUX.*done=1" $(B)/linux/logs/shell.out || { echo "LINUX SHELL TEST FAILED: runner did not observe real LINUX_SIM_DONE output" >&2; exit 1; }; grep -q "#LINUX.*cmds=1" $(B)/linux/logs/shell.out || { echo "LINUX SHELL TEST FAILED: expected command output not observed" >&2; exit 1; }; echo "TEST PASSED (L4 BusyBox shell: login, uname, cpuinfo, ls /, LINUX_SIM_DONE)"

linux_dbg_initrd: $(B)/vlt_linux_dbg/run_linux | linux linux/linux_initrd.dtb linux_pinned_kernel linux_pinned_rootfs $(B)/linux/logs
	@sha256sum linux/vmlinux.bin | grep -q $(KERNEL_SHA256) || { echo "LINUX DEBUG INITRD FAILED: kernel sha256 mismatch (expected $(KERNEL_SHA256))" >&2; exit 1; }
	@sha256sum linux/rootfs.cpio | grep -q $(ROOTFS_SHA256) || { echo "LINUX DEBUG INITRD FAILED: rootfs sha256 mismatch (expected $(ROOTFS_SHA256))" >&2; exit 1; }
	@mkdir -p $(B)/linux/logs; env LINUX_INITRD=linux/rootfs.cpio ./$(B)/vlt_linux_dbg/run_linux linux/vmlinux.bin linux/linux_initrd.dtb $(LINUX_DBG_CYCLES) prompt | tee $(B)/linux/logs/boot_dbg_initrd.out

$(B)/vlt_linux_ckpt/run_linux_ckpt: $(RTL) tb/run_linux.sv tb/run_linux.cpp | linux
	verilator --cc --exe --savable --Wall -O3 --x-assign fast --x-initial fast -DLINUX -DLINUX_CKPT -CFLAGS -DLINUX_CKPT -DCACHE_LAT=1 --top-module run_linux --Mdir $(B)/vlt_linux_ckpt -o run_linux_ckpt $(RTL) tb/run_linux.sv $(CURDIR)/tb/run_linux.cpp
	$(MAKE) -C $(B)/vlt_linux_ckpt -f Vrun_linux.mk OPT_FAST="-O3" run_linux_ckpt -j 4

linux_ckpt_hash: $(RTL) tb/run_linux.sv tb/run_linux.cpp linux/vmlinux.bin linux/linux.dtb
	@echo "LINUX_CKPT_HASH=$(LINUX_CKPT_HASH)"

linux_ckpt_save: $(B)/vlt_linux_ckpt/run_linux_ckpt linux/gate.txt | linux $(B)/linux/logs
	@mkdir -p $(B)/linux/logs $(B)/linux_ckpt
	@./$(B)/vlt_linux_ckpt/run_linux_ckpt linux/vmlinux.bin linux/linux.dtb $$(( $(LINUX_CKPT_SAVE_CYCLE)+1 )) run save $(LINUX_CKPT_FILE) $(LINUX_CKPT_HASH) | tee $(B)/linux/logs/ckpt_save.out
	@grep -q "^#CKPT_SAVE " $(B)/linux/logs/ckpt_save.out || { echo "LINUX CHECKPOINT SAVE FAILED" >&2; exit 1; }
	@sha256sum $(LINUX_CKPT_FILE) | tee $(B)/linux/logs/ckpt_save_sha.out

linux_ckpt_restore: $(B)/vlt_linux_ckpt/run_linux_ckpt $(LINUX_CKPT_FILE) | linux $(B)/linux/logs
	@mkdir -p $(B)/linux/logs
	@./$(B)/vlt_linux_ckpt/run_linux_ckpt linux/vmlinux.bin linux/linux.dtb $(LINUX_CKPT_LATER_CYCLE) run restore $(LINUX_CKPT_FILE) $(LINUX_CKPT_HASH) | tee $(B)/linux/logs/ckpt_restore.out
	@grep -q "^#CKPT_RESTORE " $(B)/linux/logs/ckpt_restore.out || { echo "LINUX CHECKPOINT RESTORE FAILED" >&2; exit 1; }
	@grep -q "^#LINUX cycles=" $(B)/linux/logs/ckpt_restore.out || { echo "LINUX CHECKPOINT RESTORE DID NOT FINISH" >&2; exit 1; }

linux_ckpt_equiv: linux_ckpt_save linux_ckpt_restore | linux $(B)/linux/logs
	@mkdir -p $(B)/linux/logs
	@./$(B)/vlt_linux_ckpt/run_linux_ckpt linux/vmlinux.bin linux/linux.dtb $(LINUX_CKPT_LATER_CYCLE) run mark $(LINUX_CKPT_SAVE_CYCLE) | tee $(B)/linux/logs/ckpt_mark.out
	@grep -q "^#CKPT_MARK " $(B)/linux/logs/ckpt_mark.out || { echo "LINUX CHECKPOINT MARK FAILED" >&2; exit 1; }
	@grep -q "^#LINUX cycles=" $(B)/linux/logs/ckpt_mark.out || { echo "LINUX CHECKPOINT MARK DID NOT FINISH" >&2; exit 1; }
	@sed -n '/^#CKPT_MARK /,$$p' $(B)/linux/logs/ckpt_mark.out | grep -v '^#CKPT_MARK ' > $(B)/linux/logs/ckpt_mark_tail.out
	@sed -n '/^#CKPT_RESTORE /,$$p' $(B)/linux/logs/ckpt_restore.out | grep -v '^#CKPT_RESTORE ' > $(B)/linux/logs/ckpt_restore_tail.out
	@diff -u $(B)/linux/logs/ckpt_mark_tail.out $(B)/linux/logs/ckpt_restore_tail.out || { echo "LINUX CHECKPOINT EQUIVALENCE FAILED" >&2; exit 1; }
	@grep -q "^#CKPT_SAVE " $(B)/linux/logs/ckpt_save.out || { echo "LINUX CHECKPOINT EQUIVALENCE: no save marker" >&2; exit 1; }
	@grep -q "^#CKPT_RESTORE " $(B)/linux/logs/ckpt_restore.out || { echo "LINUX CHECKPOINT EQUIVALENCE: no restore marker" >&2; exit 1; }
	@echo "LINUX CHECKPOINT EQUIVALENCE PASSED"

linux_dbg_ckpt: $(B)/vlt_linux_ckpt/run_linux_ckpt linux/gate.txt | linux $(B)/linux/logs
	@mkdir -p $(B)/linux/logs $(B)/linux_ckpt
	@echo "Checkpoint hash: $(LINUX_CKPT_HASH)"
	@if [ -s $(LINUX_CKPT_FILE) ]; then \
	  ./$(B)/vlt_linux_ckpt/run_linux_ckpt linux/vmlinux.bin linux/linux.dtb $(LINUX_CKPT_LATER_CYCLE) run restore $(LINUX_CKPT_FILE) $(LINUX_CKPT_HASH) | tee $(B)/linux/logs/ckpt_debug.out; \
	  if grep -q '^#CKPT_RESTORE ' $(B)/linux/logs/ckpt_debug.out; then \
	    echo "Restored from $(LINUX_CKPT_FILE) at cycle $(LINUX_CKPT_SAVE_CYCLE)."; \
	  else \
	    echo "Snapshot refused/failed; falling back to boot from cycle 0 at $$(( $(LINUX_CKPT_SAVE_CYCLE)+1 ))."; \
	    ./$(B)/vlt_linux_ckpt/run_linux_ckpt linux/vmlinux.bin linux/linux.dtb $(LINUX_CKPT_LATER_CYCLE) run mark $(LINUX_CKPT_SAVE_CYCLE) | tee -a $(B)/linux/logs/ckpt_debug.out; \
	    grep -q '^#CKPT_MARK ' $(B)/linux/logs/ckpt_debug.out || { echo "LINUX_DBG_CKPT fallback marker failed" >&2; exit 1; }; \
	  fi; \
	else \
	  echo "No checkpoint file $(LINUX_CKPT_FILE); booting from cycle 0 with debug marker at $(LINUX_CKPT_SAVE_CYCLE)."; \
	  ./$(B)/vlt_linux_ckpt/run_linux_ckpt linux/vmlinux.bin linux/linux.dtb $(LINUX_CKPT_LATER_CYCLE) platform mark $(LINUX_CKPT_SAVE_CYCLE) | tee $(B)/linux/logs/ckpt_debug.out; \
	  grep -q '^#CKPT_MARK ' $(B)/linux/logs/ckpt_debug.out || { echo "LINUX_DBG_CKPT boot marker failed" >&2; exit 1; }; \
	fi

# --- M10b Doom probe: crt0 + picolibc stdio over the fd-table fsys layer ---
$(B)/doom:
	@mkdir -p $(B)/doom

$(B)/doom/wad.bin: | need_wad $(B)/doom
	cp $(WAD_SRC) $@

$(B)/doom/wad.hex: $(B)/doom/wad.bin | $(B)/doom
	python3 tools/bin2hex.py $< $@

$(B)/doom/fsys.o: doom/fsys_rv32.c | $(B)/doom
	$(CC) $(CCFLAGS) -O1 -c --specs=picolibc.specs -o $@ $<

$(B)/doom/probe.elf: doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S tools/probe_fs.c $(B)/doom/fsys.o | $(B)/doom
	$(CC) $(CCFLAGS) -O1 -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -o $@ doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S tools/probe_fs.c $(B)/doom/fsys.o

$(B)/doom/probe.bin: $(B)/doom/probe.elf | $(B)/doom
	$(OC) -O binary $< $@

$(B)/doom/probe.hex: $(B)/doom/probe.bin | $(B)/doom
	python3 tools/bin2hex.py $< $@

$(B)/vlt_big/run_mmio_big: $(RTL) $(TB_MMIO) | $(B)/doom
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DDOOM_BIG -DUARTTRACE -DCACHE_LAT=5 --Mdir $(B)/vlt_big -o run_mmio_big $(RTL) $(TB_MMIO)

doom_probe: $(B)/vlt_big/run_mmio_big $(B)/doom/probe.hex $(B)/doom/wad.hex
	@mkdir -p $(B)/doom/logs; cp $(B)/doom/probe.hex $(B)/m7/p.hex; ./$(B)/vlt_big/run_mmio_big > $(B)/doom/logs/probe.out; grep "#UBYTE" $(B)/doom/logs/probe.out | head -n 30; grep "#UART_BYTES\|#M7SUM\|#BPSTAT" $(B)/doom/logs/probe.out

DOOM_TB := tb/run_doom.sv
DOOM_MAIN := tb/main_doom.cpp
DOOM_MAIN_ABS := $(CURDIR)/$(DOOM_MAIN)

# Doom ELF: all doom/src/*.c except the desktop-port frontends and music extras.
DOOM_EXCLUDE := doomgeneric_allegro doomgeneric_emscripten doomgeneric_linuxvt doomgeneric_sdl doomgeneric_soso doomgeneric_sosox doomgeneric_win doomgeneric_xlib gusconf mus2mid i_allegromusic i_allegrosound i_cdmus i_sdlmusic i_sdlsound
DOOM_NAMES := $(filter-out $(DOOM_EXCLUDE),$(notdir $(basename $(wildcard doom/src/*.c))))
DOOM_OBJS := $(foreach n,$(DOOM_NAMES),$(B)/doom/$(n).o)

$(B)/doom/%.o: doom/src/%.c | $(B)/doom
	$(CC) $(CCFLAGS) -O2 -c --specs=picolibc.specs -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -I doom/src -I . -o $@ $<

$(B)/doom/port_rv32.o: doom/port_rv32.c | $(B)/doom
	$(CC) $(CCFLAGS) -O2 -c --specs=picolibc.specs -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -I doom/src -o $@ $<

$(B)/doom/doom.elf: $(DOOM_OBJS) $(B)/doom/port_rv32.o $(B)/doom/fsys.o doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S | $(B)/doom
	$(CC) $(CCFLAGS) -O2 -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -o $@ doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S $(DOOM_OBJS) $(B)/doom/port_rv32.o $(B)/doom/fsys.o

$(B)/doom/doom.bin: $(B)/doom/doom.elf | $(B)/doom
	$(OC) -O binary $< $@

$(B)/doom/doom.hex: $(B)/doom/doom.bin | $(B)/doom
	python3 tools/bin2hex.py $< $@

doom_elf: $(B)/doom/doom.elf
	@echo doom_elf: $^

$(B)/doom/doom.syms: $(B)/doom/doom.elf | $(B)/doom
	@riscv64-unknown-elf-nm $< > $@

$(B)/vlt_doom/run_doom: $(RTL) $(DOOM_TB) $(DOOM_MAIN) | $(B)/doom
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast $(GFT) $(VROPT) $(THREADS) -DDOOM_BIG -DCACHE_LAT=5 -DTOPPIPE --top-module run_doom --Mdir $(B)/vlt_doom -o run_doom $(RTL) $(DOOM_TB) $(DOOM_MAIN_ABS)
	$(MAKE) -C $(B)/vlt_doom -f Vrun_doom.mk OPT_FAST="$(OPT_FAST)" run_doom -j 4

doom: $(B)/vlt_doom/run_doom $(B)/doom/doom.hex $(B)/doom/wad.hex $(B)/doom/doom.syms
	@mkdir -p $(B)/doom/frames $(B)/doom/logs
	@./$(B)/vlt_doom/run_doom 400000000 $(B)/doom/doom.hex $(B)/doom/wad.hex $(B)/doom/doom.syms $(B)/doom/logs/run.out $(B)/doom/frames || exit 1
	@grep -q "frames=31 .*halt=0" $(B)/doom/logs/run.out || { echo "DOOM 31-FRAME GATE FAILED" >&2; exit 1; }
	@grep "#frame\|#RUN" $(B)/doom/logs/run.out | tail -n 40
	@echo "TEST PASSED (Doom: 31 frames, halt=0)"

# M10f: playable Doom (SDL2 window + key FIFO MMIO). WINDOW mode: run with
# `hdl make play`; `play_test` = scripted headless verification w/ frame diff.
SDL2_LIBS := -lSDL2
GFT ?=
OPT_FAST ?= -O3
THREADS ?= --threads 1
VROPT ?=

$(B)/vlt_play/run_play: $(RTL) $(DOOM_TB) tb/play_main.cpp | $(B)
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast $(THREADS) -DDOOM_BIG -DCACHE_LAT=5 -DTOPPIPE --top-module run_doom --Mdir $(B)/vlt_play -o run_play $(RTL) $(DOOM_TB) $(CURDIR)/tb/play_main.cpp
	$(MAKE) -C $(B)/vlt_play -f Vrun_doom.mk OPT_FAST="-O3" LIBS="$(SDL2_LIBS)" run_play -j 4

play: $(B)/vlt_play/run_play $(B)/doom/doom.hex $(B)/doom/wad.hex $(B)/doom/doom.syms
	@rm -f $(B)/play/frames/frame_*.ppm; mkdir -p $(B)/play/frames $(B)/play/logs; ./$(B)/vlt_play/run_play 3000000000

PLAY_SCRIPT ?= @3000000,enter:2000000,@30000000,enter:2000000,@30000000,enter:2000000,@60000000,up:400000000
play_test: $(B)/vlt_play/run_play $(B)/doom/doom.hex $(B)/doom/wad.hex $(B)/doom/doom.syms
	@rm -rf $(B)/play $(B)/play_baseline; mkdir -p $(B)/play/logs $(B)/play/frames $(B)/play_baseline/logs $(B)/play_baseline/frames
	@PLAY_SCRIPT= ./$(B)/vlt_play/run_play 1600000000 $(B)/play_baseline | tail -n 1
	@PLAY_SCRIPT="$(PLAY_SCRIPT)" ./$(B)/vlt_play/run_play 1600000000 $(B)/play | tail -n 1
	@PLAY_SCRIPT="$(PLAY_SCRIPT)" python3 tools/play_verify.py
	@python3 tools/ppm2png.py $(B)/play/frames/frame_342.ppm=docs/doom/play_menu.png $(B)/play/frames/frame_500.ppm=docs/doom/play_move_a.png $(B)/play/frames/frame_560.ppm=docs/doom/play_move_b.png

doom_mem: $(B)/vlt_doom/run_doom $(B)/doom/doom.hex $(B)/doom/wad.hex $(B)/doom/doom.syms
	@mkdir -p $(B)/doom/frames $(B)/doom/logs
	./$(B)/vlt_doom/run_doom 400000000 $(B)/doom/doom.hex $(B)/doom/wad.hex $(B)/doom/doom.syms $(B)/doom/logs/doom_mem.out $(B)/doom/frames

lat1:
	$(MAKE) CACHE_LAT=1 test
	$(MAKE) CACHE_LAT=1 test

lat5:
	$(MAKE) CACHE_LAT=5 test

lat20:
	$(MAKE) CACHE_LAT=20 test

# D1: one target running every regression suite from the milestone rules.
all_tests:
	@BUILD_ROOT=$(B) python3 tools/run_all_tests_parallel.py

mpp_ret_test: $(B)/t23_mret_mpp.bin
	@python3 iss/iss.py --high --quiet --pass $(B)/t23_mret_mpp.bin || { echo "MPP HIGH-PC MRET RET TEST FAILED"; exit 1; }
	@echo "TEST PASSED (mret MPP: saved MPP restores the current mode; MPP leaves U after mret)"

$(B)/vlt_mpp:
	@mkdir -p $(B)/vlt_mpp $(B)/vlt_mpp/logs

$(B)/vlt_mpp/run_high_mpp: $(RTL) tb/run_hex.sv $(B)/t23_mret_mpp.hex | $(B)/vlt_mpp
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DLINUX -DHIGH_PC -DCACHE_LAT=1 -DTBHEX='"$(B)/t23_mret_mpp.hex"' --Mdir $(B)/vlt_mpp -o run_high_mpp $(RTL) tb/run_hex.sv

$(B)/vlt_mpp_std:
	@mkdir -p $(B)/vlt_mpp_std $(B)/vlt_mpp_std/logs

$(B)/vlt_mpp_std/run_high_std: $(RTL) tb/run_hex.sv $(B)/t23_mret_mpp.hex | $(B)/vlt_mpp_std
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DLINUX -DHIGH_PC -DCACHE_LAT=1 -DTBHEX='"$(B)/t23_mret_mpp.hex"' --Mdir $(B)/vlt_mpp_std -o run_high_std $(RTL) tb/run_hex.sv

mpp_ret_gate: $(B)/t23_mret_mpp.hex $(B)/t23_mret_mpp.bin $(B)/vlt_mpp/run_high_mpp $(B)/vlt_mpp_std/run_high_std
	@mkdir -p $(B)/vlt_mpp_std/logs
	@./$(B)/vlt_mpp/run_high_mpp > $(B)/vlt_mpp/logs/t23_mpp.rtl.log; grep -q 'HALT=1' $(B)/vlt_mpp/logs/t23_mpp.rtl.log || { echo "MPP LINUX_MPP RTL GATE FAILED: no halt"; exit 1; }
	@python3 iss/iss.py --high --quiet --pass --log $(B)/vlt_mpp/logs/t23_mpp.iss.log $(B)/t23_mret_mpp.bin > /dev/null || { echo "MPP HIGH-PC ISS GATE FAILED"; exit 1; }
	@python3 tools/cmp.py $(B)/vlt_mpp/logs/t23_mpp.rtl.log $(B)/vlt_mpp/logs/t23_mpp.iss.log || { echo "MPP HIGH-PC RTL/ISS MISMATCH"; exit 1; }
	@./$(B)/vlt_mpp_std/run_high_std > $(B)/vlt_mpp_std/logs/t23_std.rtl.log; grep -q 'HALT=1' $(B)/vlt_mpp_std/logs/t23_std.rtl.log || { echo "MPP STANDARD RTL GATE FAILED: no halt"; exit 1; }
	@python3 iss/iss.py --high --quiet --pass --log $(B)/vlt_mpp_std/logs/t23_std.iss.log $(B)/t23_mret_mpp.bin > /dev/null || { echo "MPP STANDARD ISS GATE FAILED"; exit 1; }
	@python3 tools/cmp.py $(B)/vlt_mpp_std/logs/t23_std.rtl.log $(B)/vlt_mpp_std/logs/t23_std.iss.log || { echo "MPP STANDARD RTL/ISS MISMATCH"; exit 1; }
	@echo "TEST PASSED (mpp_ret_gate: high-PC RTL and ISS both follow the minimal U/M MRET model)"

lint:
	verilator --lint-only -Wall --timing -DTOPPIPE $(RTL) $(TB)

clean:
	rm -rf build wave.vcd

RTL_NO_CACHE := $(filter-out rtl/cache32.sv,$(RTL))
SYN_FILES := rtl/cache32_small.sv $(RTL_NO_CACHE)
FPGA_RTL := rtl/fpga_top.sv
TB_FPGA := tb/fpga_tb.sv

$(B)/vlt/fpga_run: $(FPGA_RTL) $(TB_FPGA) | $(B)/vlt
	verilator --binary --Wall --timing -O2 --Mdir $(B)/vlt -o fpga_run $(FPGA_RTL) $(TB_FPGA)

$(B)/cpu.json: $(FPGA_RTL) | $(B)
	yosys -p 'read_verilog -sv -Irtl $(FPGA_RTL); synth_ice40 -top fpga_top -json $(B)/cpu.json; stat' > $(B)/cpu_syn.log

$(B)/cpu.asc: $(B)/cpu.json | $(B)
	nextpnr-ice40 --up5k --package sg48 --json $(B)/cpu.json --asc $(B)/cpu.asc --freq 20 > $(B)/cpu_route.log 2>&1

$(B)/cpu.bin: $(B)/cpu.asc
	icepack $(B)/cpu.asc $(B)/cpu.bin

fpga_toy_test: $(B)/vlt/fpga_run
	@echo "TOY proof test: single-cycle fpga_top card (not the full CPU); full-CPU tests are fpga_full + fpga_m/subw/control/csr gates."
	@./$(B)/vlt/fpga_run > $(B)/fpga.out; grep -q "TEST PASSED" $(B)/fpga.out

fpga_test: | fpga_toy_test
	@echo "fpga_test: legacy alias -> fpga_toy_test (toy proof top fpga_top, single-cycle)"

fpga_toy: $(B)/cpu.bin | fpga_toy_test
	@echo "LEGACY toy proof: single-cycle fpga_top card — its LC/Fmax numbers are NOT the full-CPU fpga_full results."
	@echo "$(B)/cpu.bin"
	@grep -H 'SB_LUT4 *[0-9]\|ICESTORM_RAM\|Max frequency' $(B)/cpu_syn.log $(B)/cpu_route.log

fpga: | fpga_toy
	@echo "fpga: legacy alias -> fpga_toy (toy proof top fpga_top; use fpga_full for full-CPU place/route)"

$(B)/fpga_prog.hex: $(B)/t01_basic.hex | $(B)
	@cp $(B)/t01_basic.hex $@

rtl/fpga_prog_init.sv: $(B)/fpga_prog.hex
	@python3 tools/gen_fpga_rom.py $< $@

FPGA_PIPE_RTL := rtl/fpga_pipe_top.sv rtl/cache32_fpga.sv $(filter-out rtl/mdiu_fast.sv,$(RTL_NO_CACHE)) rtl/mdiu_fpga.sv

$(B)/cpu_full.json: $(FPGA_PIPE_RTL) rtl/fpga_prog_init.sv | $(B)
	@yosys -p 'read_verilog -sv -Irtl -DFPGA $(FPGA_PIPE_RTL); synth_ice40 -dsp -top fpga_pipe_top -json $(B)/cpu_full.json; stat' > $(B)/cpu_full_syn.log

$(B)/cpu_full.asc: $(B)/cpu_full.json | $(B)
	@nextpnr-ice40 --up5k --package sg48 --json $(B)/cpu_full.json --asc $(B)/cpu_full.asc --freq $(FPGA_FREQ) --seed $(FPGA_SEED) > $(B)/cpu_full_route.log 2>&1

$(B)/cpu_full.bin: $(B)/cpu_full.asc
	@icepack $(B)/cpu_full.asc $(B)/cpu_full.bin

fpga_full: $(B)/cpu_full.bin | $(B)
	@echo "$(B)/cpu_full.bin"
	@grep -E 'ICESTORM_LC |SB_LUT4 *[0-9]|ICESTORM_RAM |Max frequency' $(B)/cpu_full_syn.log $(B)/cpu_full_route.log
	@python3 tools/fpga_netlist_check.py $(B)/cpu_full.json --baseline-lut4 $(FPGA_NETLIST_LUT4) --baseline-flops $(FPGA_NETLIST_FLOPS) --csr-min st_mepc:32 --csr-min st_mtvec:4 --csr-min st_mcause:6 --csr-min st_mie:4

$(B)/fpga_csrtrap:
	@mkdir -p $(B)/fpga_csrtrap

$(B)/fpga_csrtrap/fpga_prog_init.sv: $(B)/fpga_csrtrap.hex | $(B)/fpga_csrtrap
	@python3 tools/gen_fpga_rom.py $< $@

# The yosys read command searches $(B)/fpga_csrtrap first, then rtl/, so cache32_fpga.sv's
# `include "fpga_prog_init.sv"` resolves to the csrtrap ROM rather than rtl/fpga_prog_init.sv.
$(B)/fpga_csrtrap/cpu_full.json: $(FPGA_PIPE_RTL) $(B)/fpga_csrtrap/fpga_prog_init.sv | $(B)/fpga_csrtrap
	@yosys -p 'read_verilog -sv -DFPGA -I$(B)/fpga_csrtrap -Irtl $(FPGA_PIPE_RTL); synth_ice40 -dsp -top fpga_pipe_top -json $(B)/fpga_csrtrap/cpu_full.json; stat' > $(B)/fpga_csrtrap/cpu_full_syn.log

fpga_csrtrap_netlist: $(B)/fpga_csrtrap/cpu_full.json | $(B)/fpga_csrtrap
	@python3 tools/fpga_netlist_check.py $(B)/fpga_csrtrap/cpu_full.json --baseline-lut4 $(FPGA_CSRTRAP_NETLIST_LUT4) --baseline-flops $(FPGA_CSRTRAP_NETLIST_FLOPS) --csr-min st_mepc:32 --csr-min st_mtvec:6 --csr-min st_mcause:6 --csr-min st_mie:6
	@echo "fpga_csrtrap_netlist: $(B)/fpga_csrtrap/cpu_full.json (see $(B)/fpga_csrtrap/cpu_full_syn.log; cache32 include path is $(B)/fpga_csrtrap first, rtl second)"

# Behavioral gate for the full pipelined FPGA top (review round, 2026-11-03):
# -DFPGA Verilator build of fpga_pipe_top running the M-heavy t07_m.hex baked
# into the cache ROM INIT (fpga_m_prog_init.sv), retire log cmp.py-compared
# against ISS -> verifies the MUL/DIV rd/val values through the idex_m_go +
# SB_MAC16 MDU path (the fpga_full gate only places/routes; this one runs it).
$(B)/fpga_m:
	@mkdir -p $(B)/fpga_m

$(B)/fpga_m/fpga_m_prog_init.sv: $(B)/t07_m.hex | $(B)/fpga_m
	@python3 tools/gen_fpga_rom.py $< $@

$(B)/vlt_fpga_m/fpga_mtop: $(FPGA_PIPE_RTL) $(B)/fpga_m/fpga_m_prog_init.sv tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv | $(B)/fpga_m
	verilator --binary --Wall --timing -O2 -DFPGA -DFPGA_MPROG -I$(B)/fpga_m --Mdir $(B)/vlt_fpga_m -o fpga_mtop $(FPGA_PIPE_RTL) tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv

fpga_mgate: $(B)/vlt_fpga_m/fpga_mtop $(B)/t07_m.bin | $(B)/fpga_m
	@./$(B)/vlt_fpga_m/fpga_mtop > $(B)/fpga_m/t07_m.rtl.log; grep -q "TEST PASSED" $(B)/fpga_m/t07_m.rtl.log
	@python3 iss/iss.py --quiet --log $(B)/fpga_m/t07_m.iss.log $(B)/t07_m.bin > /dev/null
	@python3 tools/cmp.py $(B)/fpga_m/t07_m.rtl.log $(B)/fpga_m/t07_m.iss.log

$(B)/fpga_subw:
	@mkdir -p $(B)/fpga_subw

$(B)/fpga_subw/fpga_m_prog_init.sv: $(B)/t21_fpga_subw.hex | $(B)/fpga_subw
	@python3 tools/gen_fpga_rom.py $< $@

$(B)/vlt_fpga_subw/fpga_subwtop: $(FPGA_PIPE_RTL) $(B)/fpga_subw/fpga_m_prog_init.sv tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv | $(B)/fpga_subw
	verilator --binary --Wall --timing -O2 -DFPGA -DFPGA_MPROG -I$(B)/fpga_subw --Mdir $(B)/vlt_fpga_subw -o fpga_subwtop $(FPGA_PIPE_RTL) tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv

fpga_subw_gate: $(B)/vlt_fpga_subw/fpga_subwtop $(B)/t21_fpga_subw.bin | $(B)/fpga_subw
	@./$(B)/vlt_fpga_subw/fpga_subwtop > $(B)/fpga_subw/t21_fpga_subw.rtl.log; grep -q "TEST PASSED" $(B)/fpga_subw/t21_fpga_subw.rtl.log
	@python3 iss/iss.py --quiet --log $(B)/fpga_subw/t21_fpga_subw.iss.log $(B)/t21_fpga_subw.bin > /dev/null
	@python3 tools/cmp.py $(B)/fpga_subw/t21_fpga_subw.rtl.log $(B)/fpga_subw/t21_fpga_subw.iss.log

$(B)/fpga_control:
	@mkdir -p $(B)/fpga_control

$(B)/fpga_control/fpga_m_prog_init.sv: $(B)/t22_fpga_control.hex | $(B)/fpga_control
	@python3 tools/gen_fpga_rom.py $< $@

$(B)/vlt_fpga_control/fpga_controltop: $(FPGA_PIPE_RTL) $(B)/fpga_control/fpga_m_prog_init.sv tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv | $(B)/fpga_control
	verilator --binary --Wall --timing -O2 -DFPGA -DFPGA_MPROG -I$(B)/fpga_control --Mdir $(B)/vlt_fpga_control -o fpga_controltop $(FPGA_PIPE_RTL) tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv

fpga_control_gate: $(B)/vlt_fpga_control/fpga_controltop $(B)/t22_fpga_control.bin | $(B)/fpga_control
	@./$(B)/vlt_fpga_control/fpga_controltop > $(B)/fpga_control/t22_fpga_control.rtl.log; grep -q "TEST PASSED" $(B)/fpga_control/t22_fpga_control.rtl.log
	@python3 iss/iss.py --quiet --log $(B)/fpga_control/t22_fpga_control.iss.log $(B)/t22_fpga_control.bin > /dev/null
	@python3 tools/cmp.py $(B)/fpga_control/t22_fpga_control.rtl.log $(B)/fpga_control/t22_fpga_control.iss.log

$(B)/fpga_csr:
	@mkdir -p $(B)/fpga_csr

$(B)/fpga_csr/fpga_m_prog_init.sv: $(B)/t24_fpga_csr_writes.hex | $(B)/fpga_csr
	@python3 tools/gen_fpga_rom.py $(B)/t24_fpga_csr_writes.hex $(B)/fpga_csr/fpga_m_prog_init.sv

$(B)/vlt_fpga_csr/fpga_csr_top: $(FPGA_PIPE_RTL) $(B)/fpga_csr/fpga_m_prog_init.sv tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv | $(B)/fpga_csr
	verilator --binary --Wall --timing -O2 -DFPGA -DFPGA_MPROG -I$(B)/fpga_csr --Mdir $(B)/vlt_fpga_csr -o fpga_csr_top $(FPGA_PIPE_RTL) tb/fpga_pipe_tb.sv tb/sb_prims_sim.sv

fpga_csr_gate: $(B)/vlt_fpga_csr/fpga_csr_top $(B)/t24_fpga_csr_writes.bin | $(B)/fpga_csr
	@./$(B)/vlt_fpga_csr/fpga_csr_top > $(B)/fpga_csr/t24_fpga_csr_writes.rtl.log; grep -q "TEST PASSED" $(B)/fpga_csr/t24_fpga_csr_writes.rtl.log
	@python3 iss/iss.py --quiet --log $(B)/fpga_csr/t24_fpga_csr_writes.iss.log $(B)/t24_fpga_csr_writes.bin > /dev/null
	@python3 tools/cmp.py $(B)/fpga_csr/t24_fpga_csr_writes.rtl.log $(B)/fpga_csr/t24_fpga_csr_writes.iss.log

synth:
	verilator --lint-only -Wall --timing -DTOPPIPE $(RTL) $(TB)
	verilator --lint-only -Wall --timing $(RTL_SINGLE) $(TB)
	yosys -p 'read_verilog -sv -Irtl -DCACHE_LAT=2 $(SYN_FILES); synth -top top_pipe; stat'

$(B)/vlt_mdtb/mdtb: tb/mdiu_tb.sv rtl/mdiu_fpga.sv | $(B)
	verilator --binary --timing -O1 --Wall -o mdtb $(filter %.sv,$^) --Mdir $(B)/vlt_mdtb

mdiu_tb: $(B)/vlt_mdtb/mdtb
	@./$(B)/vlt_mdtb/mdtb | grep -E 'TEST (PASSED|FAILED)'

# RISCOF arch-test gate (pinned riscv-arch-test 3.9.1).  Runs the five
# suites sequentially, one PASS/FAIL line each, never opens a browser.
# The runner needs -DLINUX -DHIGH_PC so RAM and the load window are the
# 0x8000_0000 physical window the arch-test link scripts use.
RISCOF_SUITES ?= I M A Zifencei privilege
RISCOF_ENV := deps/riscv-arch-test-3.9.1/riscv-test-suite/env
RISCOF_SUITE := deps/riscv-arch-test-3.9.1/riscv-test-suite/rv32i_m

$(B)/vlt_riscof/run_hex_sig: $(RTL) tb/run_hex_sig.sv | $(B)
	verilator --binary --Wall --timing -O2 	-DTOPPIPE -DVRUNTIME -DLINUX -DHIGH_PC -DLINUX_DEBUG -DCACHE_LAT=1 -DTBHEX='"$(B)/riscof/p.hex"' -DSIGCFG='"$(B)/riscof/p.sigcfg"' -DSIGOUT='"$(B)/riscof/p.sigout"' --Mdir $(B)/vlt_riscof -o run_hex_sig $(RTL) tb/run_hex_sig.sv

riscof: $(B)/vlt_riscof/run_hex_sig
	@for s in $(RISCOF_SUITES); do \
	  wd=$(B)/riscof_work/$$s; mkdir -p $$wd; \
	  mkdir -p $(B)/riscof_work; sed 's|@ROOT@|$(shell pwd)|g' riscof/config.ini > $(B)/riscof_work/config.ini; \
	  PATH=$(shell pwd)/riscof/bin:$(shell pwd)/deps/bin:$$PATH riscof testlist --config $(shell pwd)/$(B)/riscof_work/config.ini --suite $(RISCOF_SUITE)/$$s --env $(RISCOF_ENV) --work-dir $$wd ; \
	  python3 -c "import yaml,os,sys;[os.makedirs(d['work_dir'],exist_ok=True) for d in yaml.safe_load(open(sys.argv[1])).values()]" $$wd/test_list.yaml ; \
	  PATH=$(shell pwd)/riscof/bin:$(shell pwd)/deps/bin:$$PATH riscof run --config $(shell pwd)/$(B)/riscof_work/config.ini --suite $(RISCOF_SUITE)/$$s --env $(RISCOF_ENV) --work-dir $$wd --no-browser --no-clean --testfile $$wd/test_list.yaml > $$wd/run.log 2>&1 || true ; \
	  n=$$(ls $(RISCOF_SUITE)/$$s/src/*.S | wc -l); \
	  p=$$(grep -c ": Passed" $$wd/run.log); \
	  f=$$(grep -c ": Failed" $$wd/run.log); \
	  if [ $$p = $$n ] && [ $$f = 0 ]; then echo "SUITE $$s: PASS ($$p/$$n)"; else echo "SUITE $$s: FAIL (passed $$p/$$n, failed $$f)"; fi ; \
	 done
