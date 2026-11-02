RTL := rtl/top_pipe.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mdiu_fast.sv rtl/cache32.sv rtl/regs32.sv rtl/btb.sv rtl/ldext.sv rtl/branch.sv rtl/store.sv rtl/fwd.sv rtl/ldst.sv rtl/bpif.sv rtl/ifdec.sv rtl/csrs_pipe.sv rtl/fetch_pred.sv rtl/csrs.sv
CACHE_LAT ?= 1
RTL_SINGLE := rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32.sv rtl/regs32.sv
TB  := tb/run_hex.sv
TESTS := t01_basic t02_memory t03_control t04_edge t05_jumps t06_fence t07_m t08_bp t09_csr t10_ecall t11_ebreak t12_illegal t13_timer t14_ldst_stall t15_ld_ld_br
N ?= 200
CC := riscv64-unknown-elf-gcc
CCFLAGS := -march=rv32im_zicsr -mabi=ilp32
UI_CCFLAGS := -march=rv32i_zifencei -mabi=ilp32
OC := riscv64-unknown-elf-objcopy

RVTEST_DIR ?= ../../downloads/riscv-tests/isa
WAD_SRC ?= ../../downloads/doomwad/doom1.wad
FPGA_FREQ ?= 12.5
FPGA_SEED ?= 6
UI_DIR := $(RVTEST_DIR)/rv32ui
UI_MACROS := $(RVTEST_DIR)/macros/scalar
UM_DIR := $(RVTEST_DIR)/rv32um
UM_MACROS := $(RVTEST_DIR)/macros/scalar
UI_NAMES := $(basename $(notdir $(shell ls $(UI_DIR)/*.S)))
UI_HEXES := $(foreach n,$(UI_NAMES),build/ui/$(n).hex)
UI_BINS := $(foreach n,$(UI_NAMES),build/ui/$(n).bin)
UI_LOGS := $(foreach n,$(UI_NAMES),build/ui/logs/$(n).rtl.log build/ui/logs/$(n).iss.log)

UM_CCFLAGS := -march=rv32im_zifencei -mabi=ilp32
UM_NAMES := $(basename $(notdir $(shell ls $(UM_DIR)/*.S)))
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

.PHONY: test regress lint clean synth ui um mi mdiu_tb lat1 lat5 lat20 m7 fpga fpga_test all_tests play play_test doom_mem doom_probe doom_elf fpga_full build/vlt/run_hex build/vlt/run_mmio
.PRECIOUS: build/%.o build/%.elf build/%.bin build/ui/%.rvo build/ui/%.o build/ui/%.elf build/ui/%.bin build/mi/%.rvo build/mi/%.o build/mi/%.elf build/mi/%.bin
.SECONDARY: build/%.o build/%.elf build/%.bin build/ui/%.rvo build/ui/%.o build/ui/%.elf build/ui/%.bin build/um/%.rvo build/um/%.o build/um/%.elf build/um/%.bin build/mi/%.rvo build/mi/%.o build/mi/%.elf build/mi/%.bin

build:
	@mkdir -p build

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

build/%.o: tests/%.S | build
	$(CC) $(CCFLAGS) -c $< -o build/$*.rvo
	$(OC) -O elf32-littleriscv build/$*.rvo $@

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

build/sim_%.vvp: $(RTL) $(TB) | build
	iverilog -g2012 -Wall -DTBHEX='"build/$*.hex"' -DTOPPIPE -o build/sim_$*.vvp $(RTL) $(TB)

test: $(foreach t,$(TESTS),build/$t.bin build/$t.hex) $(UI_BINS) $(UI_HEXES) $(UM_BINS) $(UM_HEXES) build/vlt/run_hex | build/ui build/ui/logs build/um build/um/logs
	@bad=0; mkdir -p build/rand; \
	for t in $(TESTS); do \
	 cp build/$$t.hex build/p.hex; ./build/vlt/run_hex > build/$$t.rtl.log; \
	 python3 iss/iss.py --quiet --log build/$$t.iss.log build/$$t.bin > /dev/null; \
	 python3 tools/cmp.py build/$$t.rtl.log build/$$t.iss.log || bad=$$((bad+1)); \
	 done; \
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
	 python3 tools/gen.py $$i build/rand/p$$i > /dev/null; cp build/rand/p$$i.hex build/p.hex; ./build/vlt/run_hex > build/rand/$$i.rtl.log; \
	 python3 iss/iss.py --quiet --log build/rand/$$i.iss.log build/rand/p$$i.bin > /dev/null; \
	 python3 tools/cmp.py build/rand/$$i.rtl.log build/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); \
	 done; \
	 if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; fi

ui: $(UI_BINS) $(UI_HEXES) build/vlt/run_hex | build/ui build/ui/logs
	@bad=0; \
  for n in $(UI_NAMES); do \
    cp build/ui/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/ui/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/ui/logs/$$n.iss.log build/ui/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/ui/logs/$$n.rtl.log build/ui/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UI PASS; else echo "UI TEST FAILED: $$bad errors"; fi

build/vlt/run_hex_lat$(CACHE_LAT): $(RTL) $(TB) | build build/vlt
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME -DCACHE_LAT=$(CACHE_LAT) --Mdir build/vlt -o run_hex_lat$(CACHE_LAT) $(RTL) $(TB)

build/vlt/run_hex: build/vlt/run_hex_lat$(CACHE_LAT)
	@cp -f $< $@

um: $(UM_BINS) $(UM_HEXES) build/vlt/run_hex | build/um build/um/logs
	@bad=0; \
  for n in $(UM_NAMES); do \
    cp build/um/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/um/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/um/logs/$$n.iss.log build/um/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/um/logs/$$n.rtl.log build/um/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UM PASS; else echo "UM TEST FAILED: $$bad errors"; fi

mi: $(MI_BINS) $(MI_HEXES) build/vlt/run_hex | build/mi build/mi/logs
	@bad=0; \
  for n in $(MI_NAMES); do \
    cp build/mi/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/mi/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/mi/logs/$$n.iss.log build/mi/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/mi/logs/$$n.rtl.log build/mi/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL MI PASS; else echo "MI TEST FAILED: $$bad errors"; fi

regress: build/vlt/run_hex
	@bad=0; mkdir -p build/rand; for i in $(shell seq 1 $(N)); do python3 tools/gen.py $$i build/rand/p$$i > /dev/null; cp build/rand/p$$i.hex build/p.hex; ./build/vlt/run_hex > build/rand/$$i.rtl.log; python3 iss/iss.py --quiet --log build/rand/$$i.iss.log build/rand/p$$i.bin > /dev/null; python3 tools/cmp.py build/rand/$$i.rtl.log build/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; fi

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
	@bad=0; mkdir -p build/m7/logs; for n in $(M7_NAMES); do cp build/m7/$$n.hex build/m7/p.hex; ./build/vlt/run_mmio > build/m7/logs/$$n.out; grep -q PASS build/m7/logs/$$n.out > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL M7 PASS; else echo "M7 TEST FAILED: $$bad errors"; fi

# --- M10b Doom probe: crt0 + picolibc stdio over the fd-table fsys layer ---
build/doom:
	@mkdir -p build/doom

build/doom/wad.bin: $(WAD_SRC) | build/doom
	cp $< $@

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
