RTL := rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32.sv rtl/regs32.sv
TB  := tb/run_hex.sv
TESTS := t01_basic t02_memory t03_control t04_edge t05_jumps t06_fence
N ?= 200
CC := riscv64-unknown-elf-gcc
CCFLAGS := -march=rv32i -mabi=ilp32
OC := riscv64-unknown-elf-objcopy

.PHONY: test regress lint clean synth
.PRECIOUS: build/%.o build/%.elf build/%.bin

build:
	@mkdir -p build

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

build/sim_%.vvp: $(RTL) $(TB) | build
	iverilog -g2012 -Wall -DTBHEX='"build/$*.hex"' -o build/sim_$*.vvp $(RTL) $(TB)

test: $(foreach t,$(TESTS),build/sim_$t.vvp) $(foreach t,$(TESTS),build/$t.hex)
	@bad=0; \
	for t in $(TESTS); do \
	  vvp build/sim_$$t.vvp > build/$$t.rtl.log 2>&1; \
	  python3 iss/iss.py --quiet --log build/$$t.iss.log build/$$t.bin > /dev/null; \
	  python3 tools/cmp.py build/$$t.rtl.log build/$$t.iss.log || bad=$$((bad+1)); \
	 done; \
	 if [ $$bad -eq 0 ]; then echo ALL PASS; else echo TEST FAILED:\ $$bad\ errors; fi

build/vlt/run_hex: $(RTL) $(TB) | build build/vlt
	verilator --binary --Wall --timing -O2 --Mdir build/vlt -o run_hex $(RTL) $(TB)

regress: build/vlt/run_hex
	@bad=0; mkdir -p build/rand; for i in $(shell seq 1 $(N)); do python3 tools/gen.py $$i build/rand/p$$i > /dev/null; cp build/rand/p$$i.hex build/p.hex; ./build/vlt/run_hex > build/rand/$$i.rtl.log; python3 iss/iss.py --quiet --log build/rand/$$i.iss.log build/rand/p$$i.bin > /dev/null; python3 tools/cmp.py build/rand/$$i.rtl.log build/rand/$$i.iss.log > /dev/null || bad=$$((bad+1)); done; if [ $$bad -eq 0 ]; then echo ALL PASS; else echo "TEST FAILED: $$bad errors"; fi

lint:
	verilator --lint-only -Wall --timing $(RTL) $(TB)

clean:
	rm -rf build wave.vcd

synth:
	verilator --lint-only -Wall --timing $(RTL) $(TB)
	yosys -p 'read_verilog -sv rtl/top_single.sv rtl/ctrl.sv rtl/imm32.sv rtl/alu.sv rtl/mem32_small.sv rtl/regs32.sv; synth -top top_single; stat'
