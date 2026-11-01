RTL := rtl/top_pipe.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32.sv rtl/regs32.sv
RTL_SINGLE := rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32.sv rtl/regs32.sv
TB  := tb/run_hex.sv
TESTS := t01_basic t02_memory t03_control t04_edge t05_jumps t06_fence
N ?= 200
CC := riscv64-unknown-elf-gcc
CCFLAGS := -march=rv32i -mabi=ilp32
UI_CCFLAGS := -march=rv32i_zifencei -mabi=ilp32
OC := riscv64-unknown-elf-objcopy

UI_DIR := /home/jemko/agent-workspace/downloads/riscv-tests/isa/rv32ui
UI_MACROS := /home/jemko/agent-workspace/downloads/riscv-tests/isa/macros/scalar
UI_NAMES := $(basename $(notdir $(shell ls $(UI_DIR)/*.S)))
UI_HEXES := $(foreach n,$(UI_NAMES),build/ui/$(n).hex)
UI_LOGS := $(foreach n,$(UI_NAMES),build/ui/logs/$(n).rtl.log build/ui/logs/$(n).iss.log)

.PHONY: test regress lint clean synth ui
.PRECIOUS: build/%.o build/%.elf build/%.bin build/ui/%.rvo build/ui/%.o build/ui/%.elf build/ui/%.bin

build:
	@mkdir -p build

build/ui:
	@mkdir -p build/ui

build/ui/logs:
	@mkdir -p build/ui/logs

build/vlt:
	@mkdir -p build/vlt

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

build/sim_%.vvp: $(RTL) $(TB) | build
	iverilog -g2012 -Wall -DTBHEX='"build/$*.hex"' -DTOPPIPE -o build/sim_$*.vvp $(RTL) $(TB)

test: $(foreach t,$(TESTS),build/sim_$t.vvp) $(foreach t,$(TESTS),build/$t.hex)
	@bad=0; \
	for t in $(TESTS); do \
	  vvp build/sim_$$t.vvp > build/$$t.rtl.log 2>&1; \
	  python3 iss/iss.py --quiet --log build/$$t.iss.log build/$$t.bin > /dev/null; \
	  python3 tools/cmp.py build/$$t.rtl.log build/$$t.iss.log || bad=$$((bad+1)); \
	 done; \
	 if [ $$bad -eq 0 ]; then echo ALL PASS; else echo TEST FAILED:\ $$bad\ errors; fi

ui: $(UI_HEXES) build/vlt/run_hex | build/ui build/ui/logs
	@bad=0; \
  for n in $(UI_NAMES); do \
    cp build/ui/$$n.hex build/p.hex; \
    ./build/vlt/run_hex > build/ui/logs/$$n.rtl.log; \
    python3 iss/iss.py --quiet --pass --log build/ui/logs/$$n.iss.log build/ui/$$n.bin > /dev/null || bad=$$((bad+1)); \
    python3 tools/cmp.py build/ui/logs/$$n.rtl.log build/ui/logs/$$n.iss.log > /dev/null || bad=$$((bad+1)); \
  done; \
  if [ $$bad -eq 0 ]; then echo ALL UI PASS; else echo "UI TEST FAILED: $$bad errors"; fi

build/vlt/run_hex: $(RTL) $(TB) | build build/vlt
	verilator --binary --Wall --timing -O2 -DTOPPIPE -DVRUNTIME --Mdir build/vlt -o run_hex $(RTL) $(TB)

regress: build/vlt/run_hex
	@bad=0; mkdir -p build/rand; for i in $(shell seq 1 $(N)); do python3 tools/gen.py $$i build/rand/p$$i > /dev/null; cp build/rand/p$$i.hex build/p.hex; ./build/vlt/run_hex > build/rand/$$i.rtl.log; python3 iss/iss.py --quiet --log build/rand/$$i.iss.log build/rand/p$$i.bin > /dev/null; python3 tools/cmp.py build/rand/$$i.rtl.log build/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; fi

lint:
	verilator --lint-only -Wall --timing -DTOPPIPE $(RTL) $(TB)

clean:
	rm -rf build wave.vcd

synth:
	verilator --lint-only -Wall --timing $(RTL) $(TB)
	yosys -p 'read_verilog -sv rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32_small.sv rtl/regs32.sv; synth -top top_single; stat'
