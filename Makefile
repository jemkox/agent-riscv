RTL := rtl/top_pipe.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mdiu_fast.sv rtl/cache32.sv rtl/regs32.sv rtl/btb.sv rtl/ldext.sv rtl/branch.sv rtl/store.sv rtl/fwd.sv rtl/ldst.sv rtl/bpif.sv rtl/ifdec.sv rtl/csrs_pipe.sv rtl/fetch_pred.sv rtl/csrs.sv rtl/clint_dev.sv
CACHE_LAT ?= 1
RTL_SINGLE := rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32.sv rtl/regs32.sv
TB  := tb/run_hex.sv
TESTS := t01_basic t02_memory t03_control t04_edge t05_jumps t06_fence t07_m t08_bp t09_csr t10_ecall t11_ebreak t12_illegal t13_timer t14_ldst_stall t15_ld_ld_br t16_mret t17_csr_fwd t18_wfi t19_amo t20_amo_illegal
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
FREERTOS_TAG ?= V11.2.0
WAD_SHA1 := 5b2e249b9c5133ec987b3ea77596381dc0d6bc1d
RVTEST_DIR ?= $(firstword $(wildcard deps/riscv-tests/isa ../../downloads/riscv-tests/isa) deps/riscv-tests/isa)
COREMARK_DIR ?= $(firstword $(wildcard deps/coremark ../../downloads/coremark) deps/coremark)
FREERTOS_DIR ?= $(firstword $(wildcard deps/FreeRTOS-Kernel ../../downloads/FreeRTOS-Kernel) deps/FreeRTOS-Kernel)
WAD_SRC ?= $(firstword $(wildcard deps/doom1.wad ../../downloads/doomwad/doom1.wad) deps/doom1.wad)
FPGA_FREQ ?= 12.5
FPGA_SEED ?= 6
UI_DIR := $(RVTEST_DIR)/rv32ui
UI_MACROS := $(RVTEST_DIR)/macros/scalar
UM_DIR := $(RVTEST_DIR)/rv32um
UM_MACROS := $(RVTEST_DIR)/macros/scalar
UI_NAMES := $(basename $(notdir $(shell ls $(UI_DIR)/*.S 2>/dev/null)))
UI_HEXES := $(foreach n,$(UI_NAMES),build/ui/$(n).hex)
UI_BINS := $(foreach n,$(UI_NAMES),build/ui/$(n).bin)
UI_LOGS := $(foreach n,$(UI_NAMES),build/ui/logs/$(n).rtl.log build/ui/logs/$(n).iss.log)

UM_CCFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32
UM_NAMES := $(basename $(notdir $(shell ls $(UM_DIR)/*.S 2>/dev/null)))
UM_HEXES := $(foreach n,$(UM_NAMES),build/um/$(n).hex)
UM_BINS := $(foreach n,$(UM_NAMES),build/um/$(n).bin)
UM_LOGS := $(foreach n,$(UM_NAMES),build/um/logs/$(n).rtl.log build/um/logs/$(n).iss.log)

MI_DIR := $(RVTEST_DIR)/rv32mi
MI_CCFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32
MI_MACROS := $(RVTEST_DIR)/macros/scalar
MI_NAMES := breakpoint csr illegal instret_overflow lh-misaligned lw-misaligned ma_addr ma_fetch mcsr sbreak scall sh-misaligned shamt sw-misaligned zicntr
MI_HEXES := $(foreach n,$(MI_NAMES),build/mi/$(n).hex)
MI_BINS := $(foreach n,$(MI_NAMES),build/mi/$(n).bin)
MI_LOGS := $(foreach n,$(MI_NAMES),build/mi/logs/$(n).rtl.log build/mi/logs/$(n).iss.log)
UA_DIR := $(RVTEST_DIR)/rv32ua
UA_CCFLAGS := -march=rv32im_a_zicsr_zifencei -mabi=ilp32
UA_MACROS := $(RVTEST_DIR)/macros/scalar
UA_NAMES := amoadd_w amoand_w amomaxu_w amomax_w amominu_w amomin_w amoor_w amoswap_w amoxor_w lrsc
UA_HEXES := $(foreach n,$(UA_NAMES),build/ua/$(n).hex)
UA_BINS := $(foreach n,$(UA_NAMES),build/ua/$(n).bin)

.PHONY: deps need_rvtests need_coremark need_wad need_freertos freertos coremark test regress lint clean synth ui um mi mdiu_tb lat1 lat5 lat20 m7 fpga fpga_test all_tests play play_test doom_mem doom_probe doom_elf fpga_full ua build/vlt/run_hex build/vlt/run_mmio
.PRECIOUS: build/%.o build/%.elf build/%.bin build/ui/%.rvo build/ui/%.o build/ui/%.elf build/ui/%.bin build/mi/%.rvo build/mi/%.o build/mi/%.elf build/mi/%.bin
.SECONDARY: build/%.o build/%.elf build/%.bin build/ui/%.rvo build/ui/%.o build/ui/%.elf build/ui/%.bin build/um/%.rvo build/um/%.o build/um/%.elf build/um/%.bin build/mi/%.rvo build/mi/%.o build/mi/%.elf build/mi/%.bin

build:
	@mkdir -p build

# --- external inputs ---
deps:
	@mkdir -p deps
	@if [ ! -d deps/riscv-tests ]; then git clone -q $(RISCV_TESTS_URL) deps/riscv-tests && git -C deps/riscv-tests checkout -q $(RISCV_TESTS_REV) && git -C deps/riscv-tests submodule -q update --init env; fi
	@if [ ! -d deps/coremark ]; then git clone -q $(COREMARK_URL) deps/coremark && git -C deps/coremark checkout -q $(COREMARK_REV); fi
	@if [ ! -d deps/FreeRTOS-Kernel ]; then git -c advice.detachedHead=false clone -q --depth 1 --branch $(FREERTOS_TAG) $(FREERTOS_URL) deps/FreeRTOS-Kernel; fi
	@echo "deps: riscv-tests $$(git -C deps/riscv-tests rev-parse --short HEAD), coremark $$(git -C deps/coremark rev-parse --short HEAD), FreeRTOS $$(git -C deps/FreeRTOS-Kernel describe --tags)"
	@[ -f deps/doom1.wad ] && echo "deps: doom1.wad present" || echo "deps: for Doom, copy the shareware doom1.wad (v1.9, sha1 $(WAD_SHA1)) to deps/doom1.wad"

need_rvtests:
	@[ -f $(RVTEST_DIR)/rv32ui/addi.S ] || { echo "riscv-tests not found at $(RVTEST_DIR): run 'make deps' or pass RVTEST_DIR=path/to/riscv-tests/isa" >&2; exit 1; }
	@[ -f $(RVTEST_DIR)/../env/encoding.h ] || { echo "riscv-tests env/ submodule missing: git -C $(RVTEST_DIR)/.. submodule update --init env" >&2; exit 1; }

need_coremark:
	@[ -f $(COREMARK_DIR)/core_main.c ] || { echo "CoreMark not found at $(COREMARK_DIR): run 'make deps' or pass COREMARK_DIR=path/to/coremark" >&2; exit 1; }

need_wad:
	@[ -f "$(WAD_SRC)" ] || { echo "doom1.wad not found at $(WAD_SRC): copy the shareware WAD (v1.9) to deps/doom1.wad or pass WAD_SRC=path" >&2; exit 1; }
	@echo "$(WAD_SHA1)  $(WAD_SRC)" | sha1sum -c --quiet - || { echo "$(WAD_SRC) is not the v1.9 shareware doom1.wad (sha1 $(WAD_SHA1))" >&2; exit 1; }

build/ui:
	@mkdir -p build/ui

build/ui/logs:
	@mkdir -p build/ui/logs

build/um:
	@mkdir -p build/um

build/um/logs:
	@mkdir -p build/um/logs

build/vlt:
	@mkdir -p build/vlt

build/mi:
	@mkdir -p build/mi

build/mi/logs:
	@mkdir -p build/mi/logs

build/ua:
	@mkdir -p build/ua

build/ua/logs:
	@mkdir -p build/ua/logs

build/%.o: tests/%.S | build
	$(CC) $(CCFLAGS) -c $< -o build/$*.rvo
	$(OC) -O elf32-littleriscv build/$*.rvo $@

# t19: atomics need the A extension (rv32ima) in the assembler march
T19_CCFLAGS := -march=rv32ima_zicsr -mabi=ilp32
build/t19_amo.o: tests/t19_amo.S | build
	$(CC) $(T19_CCFLAGS) -c $< -o build/t19_amo.rvo
	$(OC) -O elf32-littleriscv build/t19_amo.rvo $@

# t20: reserved atomics and MMIO atomic traps need the A extension too
T20_CCFLAGS := -march=rv32ima_zicsr -mabi=ilp32
build/t20_amo_illegal.o: tests/t20_amo_illegal.S | build
	$(CC) $(T20_CCFLAGS) -c $< -o build/t20_amo_illegal.rvo
	$(OC) -O elf32-littleriscv build/t20_amo_illegal.rvo $@

build/%.elf: build/%.o tests/link.ld | build
	$(CC) $(CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

build/%.bin: build/%.elf | build
	$(OC) -O binary $< $@

build/%.hex: build/%.bin | build
	python3 tools/bin2hex.py $< $@

build/ui/%.o: $(UI_DIR)/%.S env/riscv_test.h | build/ui
	$(CC) $(UI_CCFLAGS) -c $< -I env -I $(UI_MACROS) -o build/ui/$*.rvo
	$(OC) -O elf32-littleriscv build/ui/$*.rvo $@

build/ui/%.elf: build/ui/%.o tests/link.ld | build/ui
	$(CC) $(UI_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

build/ui/%.bin: build/ui/%.elf | build/ui
	$(OC) -O binary $< $@

build/ui/%.hex: build/ui/%.bin | build/ui
	python3 tools/bin2hex.py $< $@

build/um/%.o: $(UM_DIR)/%.S env/riscv_test.h | build/um
	$(CC) $(UM_CCFLAGS) -c $< -I env -I $(UM_MACROS) -o build/um/$*.rvo
	$(OC) -O elf32-littleriscv build/um/$*.rvo $@

build/um/%.elf: build/um/%.o tests/link.ld | build/um
	$(CC) $(UM_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

build/um/%.bin: build/um/%.elf | build/um
	$(OC) -O binary $< $@

build/um/%.hex: build/um/%.bin | build/um
	python3 tools/bin2hex.py $< $@

build/mi/%.o: $(MI_DIR)/%.S env/mi/riscv_test.h | build/mi
	$(CC) $(MI_CCFLAGS) -c $< -I env/mi -I $(RVTEST_DIR)/../env -I $(MI_MACROS) -o build/mi/$*.rvo
	$(OC) -O elf32-littleriscv build/mi/$*.rvo $@

build/mi/%.elf: build/mi/%.o tests/link.ld | build/mi
	$(CC) $(MI_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

build/mi/%.bin: build/mi/%.elf | build/mi
	$(OC) -O binary $< $@

build/mi/%.hex: build/mi/%.bin | build/mi
	python3 tools/bin2hex.py $< $@

build/ua/%.o: $(UA_DIR)/%.S env/riscv_test.h | build/ua
	$(CC) $(UA_CCFLAGS) -c $< -I env -I $(UA_MACROS) -o build/ua/$*.rvo
	$(OC) -O elf32-littleriscv build/ua/$*.rvo $@

build/ua/%.elf: build/ua/%.o tests/link.ld | build/ua
	$(CC) $(UA_CCFLAGS) -nostdlib -Wl,-Ttests/link.ld -Wl,-m,elf32lriscv -o $@ $<

build/ua/%.bin: build/ua/%.elf | build/ua
	$(OC) -O binary $< $@

build/ua/%.hex: build/ua/%.bin | build/ua
	python3 tools/bin2hex.py $< $@


build/sim_%.vvp: $(RTL) $(TB) | build
	iverilog -g2012 -Wall -DTBHEX='"build/$*.hex"' -DTOPPIPE -o build/sim_$*.vvp $(RTL) $(TB)

test: $(foreach t,$(TESTS),build/$t.bin build/$t.hex) $(UI_BINS) $(UI_HEXES) $(UM_BINS) $(UM_HEXES) build/vlt/run_hex | need_rvtests build/ui build/ui/logs build/um build/um/logs
	@bad=0; mkdir -p build/rand; \
	for t in $(TESTS); do \
	 cp build/$$t.hex build/p.hex; ./build/vlt/run_hex > build/$$t.rtl.log; \
	 python3 iss/iss.py --quiet --log build/$$t.iss.log build/$$t.bin > /dev/null; \
	 python3 tools/cmp.py build/$$t.rtl.log build/$$t.iss.log || bad=$$((bad+1)); \
	 done; \
	 python3 iss/iss.py --quiet --pass build/t16_mret.bin > /dev/null || { echo "t16_mret: mret did not return to mepc"; bad=$$((bad+1)); }; \
	 python3 iss/iss.py --quiet --pass build/t18_wfi.bin > /dev/null || { echo "t18_wfi: self-check branch taken (gp!=1)"; bad=$$((bad+1)); }; \
	 python3 iss/iss.py --quiet --pass build/t19_amo.bin > /dev/null || { echo "t19_amo: atomics self-check branch taken (gp!=1)"; bad=$$((bad+1)); }; \
	 python3 iss/iss.py --quiet --pass build/t20_amo_illegal.bin > /dev/null || { echo "t20_amo_illegal: illegal/reserved/MMIO atomics self-check branch taken (gp!=1)"; bad=$$((bad+1)); }; \
	 for n in $(UI_NAMES); do \
	 cp build/ui/$$n.hex build/p.hex; ./build/vlt/run_hex > build/ui/logs/$$n.rtl.log; \
	 python3 iss/iss.py --quiet --pass --log build/ui/logs/$$n.iss.log build/ui/$$n.bin > /dev/null; \
	 python3 tools/cmp.py build/ui/logs/$$n.rtl.log build/ui/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 for n in $(UM_NAMES); do \
	 cp build/um/$$n.hex build/p.hex; ./build/vlt/run_hex > build/um/logs/$$n.rtl.log; \
	 python3 iss/iss.py --quiet --pass --log build/um/logs/$$n.iss.log build/um/$$n.bin > /dev/null; \
	 python3 tools/cmp.py build/um/logs/$$n.rtl.log build/um/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 for i in $(shell seq 1 $(N)); do \
 	 python3 tools/gen.py $$i build/rand/p$$i > /dev/null || bad=$$((bad+1)); cp build/rand/p$$i.hex build/p.hex; ./build/vlt/run_hex > build/rand/$$i.rtl.log; \
	 python3 iss/iss.py --quiet --log build/rand/$$i.iss.log build/rand/p$$i.bin > /dev/null; \
	 python3 tools/cmp.py build/rand/$$i.rtl.log build/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; exit 1; fi

ui: $(UI_BINS) $(UI_HEXES) build/vlt/run_hex | need_rvtests build/ui build/ui/logs
	@bad=0; \
  for n in $(UI_NAMES); do \
    cp build/ui/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/ui/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/ui/logs/$$n.iss.log build/ui/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/ui/logs/$$n.rtl.log build/ui/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UI PASS; else echo "UI TEST FAILED: $$bad errors"; exit 1; fi

build/vlt/run_hex_lat$(CACHE_LAT): $(RTL) $(TB) | build build/vlt
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DCACHE_LAT=$(CACHE_LAT) --Mdir build/vlt -o run_hex_lat$(CACHE_LAT) $(RTL) $(TB)

build/vlt/run_hex: build/vlt/run_hex_lat$(CACHE_LAT)
	@cp -f $< $@

um: $(UM_BINS) $(UM_HEXES) build/vlt/run_hex | need_rvtests build/um build/um/logs
	@bad=0; \
  for n in $(UM_NAMES); do \
    cp build/um/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/um/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/um/logs/$$n.iss.log build/um/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/um/logs/$$n.rtl.log build/um/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UM PASS; else echo "UM TEST FAILED: $$bad errors"; exit 1; fi

mi: $(MI_BINS) $(MI_HEXES) build/vlt/run_hex | need_rvtests build/mi build/mi/logs
	@bad=0; \
  for n in $(MI_NAMES); do \
    cp build/mi/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/mi/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/mi/logs/$$n.iss.log build/mi/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/mi/logs/$$n.rtl.log build/mi/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL MI PASS; else echo "MI TEST FAILED: $$bad errors"; exit 1; fi

ua: $(UA_BINS) $(UA_HEXES) build/vlt/run_hex | need_rvtests build/ua build/ua/logs
	@bad=0;   for n in $(UA_NAMES); do     cp build/ua/$$n.hex build/p.hex;     ./build/vlt/run_hex > build/ua/logs/$$n.rtl.log;     python3 iss/iss.py --quiet --pass --log build/ua/logs/$$n.iss.log build/ua/$$n.bin > /dev/null || bad=$$((bad+1));     python3 tools/cmp.py build/ua/logs/$$n.rtl.log build/ua/logs/$$n.iss.log > /dev/null || bad=$$((bad+1));   done;   if [ $$bad -eq 0 ]; then echo ALL UA PASS; else echo "UA TEST FAILED: $$bad errors"; exit 1; fi

regress: build/vlt/run_hex
	@bad=0; mkdir -p build/rand; for i in $(shell seq 1 $(N)); do python3 tools/gen.py $$i build/rand/p$$i > /dev/null || bad=$$((bad+1)); cp build/rand/p$$i.hex build/p.hex; ./build/vlt/run_hex > build/rand/$$i.rtl.log; python3 iss/iss.py --quiet --log build/rand/$$i.iss.log build/rand/p$$i.bin > /dev/null; python3 tools/cmp.py build/rand/$$i.rtl.log build/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; exit 1; fi

TB_MMIO := tb/run_mmio.sv
M7_NAMES := hello fib sort matmul bench
M7_CFLAGS := $(CCFLAGS) -O2 -fno-plt -fno-stack-protector -Iprograms
M7_HEXS := $(foreach n,$(M7_NAMES),build/m7/$(n).hex)

build/m7:
	@mkdir -p build/m7

build/m7/crt0.o: programs/crt0.S | build/m7
	$(CC) $(CCFLAGS) -c $< -o $@

build/m7/%.o: programs/%.c | build/m7
	$(CC) $(M7_CFLAGS) -c $< -o $@

build/m7/%.elf: build/m7/%.o build/m7/crt0.o tools/m7.ld | build/m7
	$(CC) $(M7_CFLAGS) -nostdlib -nostartfiles -Wl,-Ttools/m7.ld -Wl,-m,elf32lriscv -o $@ build/m7/crt0.o $<

build/m7/%.bin: build/m7/%.elf | build/m7
	$(OC) -O binary $< $@

build/m7/%.hex: build/m7/%.bin | build/m7
	python3 tools/bin2hex.py $< $@

build/vlt/run_mmio_lat$(CACHE_LAT): $(RTL) $(TB_MMIO) | build/vlt
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DCACHE_LAT=$(CACHE_LAT) --Mdir build/vlt -o run_mmio_lat$(CACHE_LAT) $(RTL) $(TB_MMIO)

build/vlt/run_mmio: build/vlt/run_mmio_lat$(CACHE_LAT)
	@cp -f $< $@

m7: build/vlt/run_mmio $(M7_HEXS)
	@bad=0; mkdir -p build/m7/logs; for n in $(M7_NAMES); do cp build/m7/$$n.hex build/m7/p.hex; ./build/vlt/run_mmio > build/m7/logs/$$n.out; grep -q PASS build/m7/logs/$$n.out > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL M7 PASS; else echo "M7 TEST FAILED: $$bad errors"; exit 1; fi

# --- CoreMark (EEMBC) on the Doom-configuration CPU (16+16 KB caches, CACHE_LAT=5) ---
# COREMARK_DIR: an upstream checkout of https://github.com/eembc/coremark (port files in bench/coremark).
COREMARK_DIR ?= ../../downloads/coremark
CM_ITER ?= 500
CM_OPT ?= -O2
CM_SRCS := $(addprefix $(COREMARK_DIR)/,core_list_join.c core_main.c core_matrix.c core_state.c core_util.c) \
           bench/coremark/core_portme.c bench/coremark/ee_printf.c bench/coremark/cvt.c
CM_FLAGS := $(CCFLAGS) $(CM_OPT) -DITERATIONS=$(CM_ITER) -DPERFORMANCE_RUN=1 -DFLAGS_STR='"$(CM_OPT)"'

build/bench:
	@mkdir -p build/bench

build/bench/coremark.elf: $(CM_SRCS) bench/coremark/core_portme.h doom/crt0_rv32.S doom/exit_rv.S doom/ld.ld | build/bench
	$(CC) $(CM_FLAGS) -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -I bench/coremark -I $(COREMARK_DIR) -o $@ doom/crt0_rv32.S doom/exit_rv.S $(CM_SRCS)

build/bench/coremark.bin: build/bench/coremark.elf
	$(OC) -O binary $< $@

build/bench/coremark.hex: build/bench/coremark.bin
	python3 tools/bin2hex.py $< $@

build/vlt_bench/run_bench: $(RTL) tb/run_doom.sv tb/bench_main.cpp | build
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast -DDOOM_BIG -DCACHE_LAT=5 -DTOPPIPE --top-module run_doom --Mdir build/vlt_bench -o run_bench $(RTL) tb/run_doom.sv $(CURDIR)/tb/bench_main.cpp
	$(MAKE) -C build/vlt_bench -f Vrun_doom.mk OPT_FAST="-O3" run_bench -j 4

coremark: need_coremark build/vlt_bench/run_bench build/bench/coremark.hex
	@./build/vlt_bench/run_bench build/bench/coremark.hex | tee build/bench/coremark.out
	@python3 tools/coremark_score.py build/bench/coremark.out

# --- FreeRTOS demo on the same CPU configuration as Doom and CoreMark (stock port) ---
RTOS_PORT_DIR := $(FREERTOS_DIR)/portable/GCC/RISC-V
RTOS_CHIP_DIR := $(RTOS_PORT_DIR)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
RTOS_SRCS := $(addprefix $(FREERTOS_DIR)/,tasks.c queue.c list.c timers.c portable/MemMang/heap_4.c) \
             $(RTOS_PORT_DIR)/port.c os/freertos/main.c
RTOS_FLAGS := $(CCFLAGS) -O2 -I os/freertos -I $(RTOS_PORT_DIR) -I $(RTOS_CHIP_DIR) -I $(FREERTOS_DIR)/include
RTOS_ASM_FLAGS := $(CCFLAGS) -O2 -I $(RTOS_PORT_DIR) -I $(RTOS_CHIP_DIR) -I $(FREERTOS_DIR)/include

need_freertos:
	@[ -f $(FREERTOS_DIR)/tasks.c ] || { echo "FreeRTOS not found at $(FREERTOS_DIR): run 'make deps' or pass FREERTOS_DIR=path/to/FreeRTOS-Kernel" >&2; exit 1; }

build/bench/portASM.o: $(RTOS_PORT_DIR)/portASM.S $(RTOS_CHIP_DIR)/freertos_risc_v_chip_specific_extensions.h | build/bench
	$(CC) $(RTOS_ASM_FLAGS) -c $< -o $@

build/bench/freertos.elf: $(RTOS_SRCS) build/bench/portASM.o $(RTOS_PORT_DIR)/portASM.S $(RTOS_PORT_DIR)/portmacro.h $(RTOS_CHIP_DIR)/freertos_risc_v_chip_specific_extensions.h os/freertos/crt0.S os/freertos/FreeRTOSConfig.h doom/exit_rv.S doom/ld.ld | build/bench
	$(CC) $(RTOS_FLAGS) -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -o $@ os/freertos/crt0.S doom/exit_rv.S build/bench/portASM.o $(RTOS_SRCS)

build/bench/freertos.bin: build/bench/freertos.elf
	$(OC) -O binary $< $@

build/bench/freertos.hex: build/bench/freertos.bin
	python3 tools/bin2hex.py $< $@

freertos: need_freertos build/vlt_bench/run_bench build/bench/freertos.hex
	@./build/vlt_bench/run_bench build/bench/freertos.hex 400000000 | tee build/bench/freertos.out
	@grep -q "^FREERTOS PASS" build/bench/freertos.out || { echo "FREERTOS TEST FAILED" >&2; exit 1; }

# --- M10b Doom probe: crt0 + picolibc stdio over the fd-table fsys layer ---
build/doom:
	@mkdir -p build/doom

build/doom/wad.bin: | need_wad build/doom
	cp $(WAD_SRC) $@

build/doom/wad.hex: build/doom/wad.bin | build/doom
	python3 tools/bin2hex.py $< $@

build/doom/fsys.o: doom/fsys_rv32.c | build/doom
	$(CC) $(CCFLAGS) -O1 -c --specs=picolibc.specs -o $@ $<

build/doom/probe.elf: doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S tools/probe_fs.c build/doom/fsys.o | build/doom
	$(CC) $(CCFLAGS) -O1 -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -o $@ doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S tools/probe_fs.c build/doom/fsys.o

build/doom/probe.bin: build/doom/probe.elf | build/doom
	$(OC) -O binary $< $@

build/doom/probe.hex: build/doom/probe.bin | build/doom
	python3 tools/bin2hex.py $< $@

build/vlt_big/run_mmio_big: $(RTL) $(TB_MMIO) | build/doom
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DDOOM_BIG -DUARTTRACE -DCACHE_LAT=5 --Mdir build/vlt_big -o run_mmio_big $(RTL) $(TB_MMIO)

doom_probe: build/vlt_big/run_mmio_big build/doom/probe.hex build/doom/wad.hex
	@mkdir -p build/doom/logs; cp build/doom/probe.hex build/m7/p.hex; ./build/vlt_big/run_mmio_big > build/doom/logs/probe.out; grep "#UBYTE" build/doom/logs/probe.out | head -n 30; grep "#UART_BYTES\|#M7SUM\|#BPSTAT" build/doom/logs/probe.out

DOOM_TB := tb/run_doom.sv
DOOM_MAIN := tb/main_doom.cpp
DOOM_MAIN_ABS := $(CURDIR)/$(DOOM_MAIN)

# Doom ELF: all doom/src/*.c except the desktop-port frontends and music extras.
DOOM_EXCLUDE := doomgeneric_allegro doomgeneric_emscripten doomgeneric_linuxvt doomgeneric_sdl doomgeneric_soso doomgeneric_sosox doomgeneric_win doomgeneric_xlib gusconf mus2mid i_allegromusic i_allegrosound i_cdmus i_sdlmusic i_sdlsound
DOOM_NAMES := $(filter-out $(DOOM_EXCLUDE),$(notdir $(basename $(wildcard doom/src/*.c))))
DOOM_OBJS := $(foreach n,$(DOOM_NAMES),build/doom/$(n).o)

build/doom/%.o: doom/src/%.c | build/doom
	$(CC) $(CCFLAGS) -O2 -c --specs=picolibc.specs -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -I doom/src -I . -o $@ $<

build/doom/port_rv32.o: doom/port_rv32.c | build/doom
	$(CC) $(CCFLAGS) -O2 -c --specs=picolibc.specs -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -I doom/src -o $@ $<

build/doom/doom.elf: $(DOOM_OBJS) build/doom/port_rv32.o build/doom/fsys.o doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S | build/doom
	$(CC) $(CCFLAGS) -O2 -static -nostartfiles -T doom/ld.ld -Wl,-m,elf32lriscv --specs=picolibc.specs -o $@ doom/crt0_rv32.S doom/exit_rv.S doom/stdout_sym.S $(DOOM_OBJS) build/doom/port_rv32.o build/doom/fsys.o

build/doom/doom.bin: build/doom/doom.elf | build/doom
	$(OC) -O binary $< $@

build/doom/doom.hex: build/doom/doom.bin | build/doom
	python3 tools/bin2hex.py $< $@

doom_elf: build/doom/doom.elf
	@echo doom_elf: $^

build/doom/doom.syms: build/doom/doom.elf | build/doom
	@riscv64-unknown-elf-nm $< > $@

build/vlt_doom/run_doom: $(RTL) $(DOOM_TB) $(DOOM_MAIN) | build/doom
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast $(GFT) $(VROPT) $(THREADS) -DDOOM_BIG -DCACHE_LAT=5 -DTOPPIPE --top-module run_doom --Mdir build/vlt_doom -o run_doom $(RTL) $(DOOM_TB) $(DOOM_MAIN_ABS)
	$(MAKE) -C build/vlt_doom -f Vrun_doom.mk OPT_FAST="$(OPT_FAST)" run_doom -j 4

doom: build/vlt_doom/run_doom build/doom/doom.hex build/doom/wad.hex build/doom/doom.syms
	@mkdir -p build/doom/frames build/doom/logs; ./build/vlt_doom/run_doom 400000000; grep "#frame\|#RUN" build/doom/logs/run.out | tail -n 40

# M10f: playable Doom (SDL2 window + key FIFO MMIO). WINDOW mode: run with
# `hdl make play`; `play_test` = scripted headless verification w/ frame diff.
SDL2_LIBS := -lSDL2
GFT ?=
OPT_FAST ?= -O3
THREADS ?= --threads 1
VROPT ?=

build/vlt_play/run_play: $(RTL) $(DOOM_TB) tb/play_main.cpp | build
	verilator --cc --exe --Wall -O3 --x-assign fast --x-initial fast $(THREADS) -DDOOM_BIG -DCACHE_LAT=5 -DTOPPIPE --top-module run_doom --Mdir build/vlt_play -o run_play $(RTL) $(DOOM_TB) $(CURDIR)/tb/play_main.cpp
	$(MAKE) -C build/vlt_play -f Vrun_doom.mk OPT_FAST="-O3" LIBS="$(SDL2_LIBS)" run_play -j 4

play: build/vlt_play/run_play build/doom/doom.hex build/doom/wad.hex build/doom/doom.syms
	@rm -f build/play/frames/frame_*.ppm; mkdir -p build/play/frames build/play/logs; ./build/vlt_play/run_play 3000000000

PLAY_SCRIPT ?= @3000000,enter:2000000,@30000000,enter:2000000,@30000000,enter:2000000,@60000000,up:400000000
play_test: build/vlt_play/run_play build/doom/doom.hex build/doom/wad.hex build/doom/doom.syms
	@rm -rf build/play build/play_baseline; mkdir -p build/play/logs build/play/frames build/play_baseline/logs build/play_baseline/frames
	@PLAY_SCRIPT= ./build/vlt_play/run_play 1600000000 build/play_baseline | tail -n 1
	@PLAY_SCRIPT="$(PLAY_SCRIPT)" ./build/vlt_play/run_play 1600000000 build/play | tail -n 1
	@PLAY_SCRIPT="$(PLAY_SCRIPT)" python3 tools/play_verify.py
	@python3 tools/ppm2png.py build/play/frames/frame_342.ppm=docs/doom/play_menu.png build/play/frames/frame_500.ppm=docs/doom/play_move_a.png build/play/frames/frame_560.ppm=docs/doom/play_move_b.png

doom_mem: build/vlt_doom/run_doom | build
	./build/vlt_doom/run_doom

lat1:
	$(MAKE) CACHE_LAT=1 test
	$(MAKE) CACHE_LAT=1 test

lat5:
	$(MAKE) CACHE_LAT=5 test

lat20:
	$(MAKE) CACHE_LAT=20 test

# D1: one target running every regression suite from the milestone rules.
all_tests:
	@echo "== [1/6] test (CACHE_LAT=1) =="
	$(MAKE) test
	@echo "== [2/6] test CACHE_LAT=5 =="
	$(MAKE) CACHE_LAT=5 test
	@echo "== [3/6] ui um mi =="
	$(MAKE) ui um mi
	@echo "== [4/6] regress N=500 =="
	$(MAKE) regress N=500
	@echo "== [5/6] m7 =="
	$(MAKE) m7
	@echo "== [6/6] doom (31 frames) =="
	$(MAKE) doom
	@echo "ALL TESTS DONE"

lint:
	verilator --lint-only -Wall --timing -DTOPPIPE $(RTL) $(TB)

clean:
	rm -rf build wave.vcd

RTL_NO_CACHE := $(filter-out rtl/cache32.sv,$(RTL))
SYN_FILES := rtl/cache32_small.sv $(RTL_NO_CACHE)
FPGA_RTL := rtl/fpga_top.sv
TB_FPGA := tb/fpga_tb.sv

build/vlt/fpga_run: $(FPGA_RTL) $(TB_FPGA) | build/vlt
	verilator --binary --Wall --timing -O2 --Mdir build/vlt -o fpga_run $(FPGA_RTL) $(TB_FPGA)

build/cpu.json: $(FPGA_RTL) | build
	yosys -p 'read_verilog -sv -Irtl $(FPGA_RTL); synth_ice40 -top fpga_top -json build/cpu.json; stat' > build/cpu_syn.log

build/cpu.asc: build/cpu.json | build
	nextpnr-ice40 --up5k --package sg48 --json build/cpu.json --asc build/cpu.asc --freq 20 > build/cpu_route.log 2>&1

build/cpu.bin: build/cpu.asc
	icepack build/cpu.asc build/cpu.bin

fpga_test: build/vlt/fpga_run
	@./build/vlt/fpga_run > build/fpga.out; grep -q "TEST PASSED" build/fpga.out

fpga: build/cpu.bin | fpga_test
	@echo "build/cpu.bin"
	@grep -H 'SB_LUT4 *[0-9]\|ICESTORM_RAM\|Max frequency' build/cpu_syn.log build/cpu_route.log

build/fpga_prog.hex: build/t01_basic.hex | build
	@cp build/t01_basic.hex $@

rtl/fpga_prog_init.sv: build/fpga_prog.hex
	@python3 tools/gen_fpga_rom.py $< $@

FPGA_PIPE_RTL := rtl/fpga_pipe_top.sv rtl/cache32_fpga.sv $(filter-out rtl/mdiu_fast.sv,$(RTL_NO_CACHE)) rtl/mdiu_fpga.sv

build/cpu_full.json: $(FPGA_PIPE_RTL) rtl/fpga_prog_init.sv | build
	@yosys -p 'read_verilog -sv -Irtl -DFPGA $(FPGA_PIPE_RTL); synth_ice40 -dsp -top fpga_pipe_top -json build/cpu_full.json; stat' > build/cpu_full_syn.log

build/cpu_full.asc: build/cpu_full.json | build
	@nextpnr-ice40 --up5k --package sg48 --json build/cpu_full.json --asc build/cpu_full.asc --freq $(FPGA_FREQ) --seed $(FPGA_SEED) > build/cpu_full_route.log 2>&1

build/cpu_full.bin: build/cpu_full.asc
	@icepack build/cpu_full.asc build/cpu_full.bin

fpga_full: build/cpu_full.bin | build
	@echo "build/cpu_full.bin"
	@grep -E 'ICESTORM_LC |SB_LUT4 *[0-9]|ICESTORM_RAM |Max frequency' build/cpu_full_syn.log build/cpu_full_route.log

synth:
	verilator --lint-only -Wall --timing -DTOPPIPE $(RTL) $(TB)
	verilator --lint-only -Wall --timing $(RTL_SINGLE) $(TB)
	yosys -p 'read_verilog -sv -Irtl -DCACHE_LAT=2 $(SYN_FILES); synth -top top_pipe; stat'

build/vlt_mdtb/mdtb: tb/mdiu_tb.sv rtl/mdiu_fpga.sv | build
	verilator --binary --timing -O1 --Wall -o mdtb $(filter %.sv,$^) --Mdir build/vlt_mdtb

mdiu_tb: build/vlt_mdtb/mdtb
	@./build/vlt_mdtb/mdtb | grep -E 'TEST (PASSED|FAILED)'
