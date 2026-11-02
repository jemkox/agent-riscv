// Benchmark runner: the same CPU configuration as the Doom runner (DOOM_BIG:
// 16 KB I + 16 KB D caches, CACHE_LAT=5, 32 MB RAM), loads one program hex at
// address 0, prints UART bytes (MMIO 0x1FF00000) to stdout, stops on halt.
// Usage: run_bench <prog.hex> [max_cycles]
#include <verilated.h>
#include <memory>
#include "Vrun_doom.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <vector>

static bool load_hex(const char *path, std::vector<uint32_t> &out) {
    FILE *f = fopen(path, "r");
    if (!f) return false;
    unsigned v;
    while (fscanf(f, "%x", &v) == 1) out.push_back(v);
    fclose(f);
    return true;
}

int main(int argc, char **argv) {
    if (argc < 2) { printf("usage: run_bench <prog.hex> [max_cycles]\n"); return 2; }
    Verilated::commandArgs(argc, argv);
    std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    std::unique_ptr<Vrun_doom> model{new Vrun_doom(contextp.get())};

    std::vector<uint32_t> prog;
    if (!load_hex(argv[1], prog)) { printf("cannot read %s\n", argv[1]); return 1; }
    const uint64_t max_cycles = (argc > 2) ? atoll(argv[2]) : 2000000000ull;
    const uint32_t UART_ADDR = 0x1FF00000u;

    auto setc = [&](uint32_t clk, uint32_t reset, uint32_t lwe, uint32_t lwa, uint32_t lwd) {
        model->clk = clk; model->reset = reset;
        model->lwe = lwe; model->lwa = lwa; model->lwd = lwd;
        model->dbg_re = 0; model->dbg_ra = 0; model->key_in = 0;
    };

    setc(0, 1, 0, 0, 0);
    model->eval();
    for (size_t i = 0; i < prog.size(); i++) {
        if (!prog[i]) continue;
        setc(1, 1, 1, 4u * (uint32_t)i, prog[i]); model->eval();
        setc(0, 1, 1, 4u * (uint32_t)i, prog[i]); model->eval();
    }
    setc(1, 1, 0, 0, 0); model->eval();
    setc(0, 0, 0, 0, 0); model->eval();

    uint64_t cyc = 0, insn = 0;
    while (cyc < max_cycles) {
        setc(1, 0, 0, 0, 0);
        model->eval();
        if (model->rv_valid) insn++;
        if (model->ex_st && model->ex_sa == UART_ADDR && (model->ex_sbe & 1)) {
            putchar((char)(model->ex_sd & 0xFF));
            fflush(stdout);
        }
        if (model->halt) break;
        setc(0, 0, 0, 0, 0);
        model->eval();
        cyc++;
    }
    printf("#BENCH cycles=%llu insns=%llu IPC=%.3f halt=%d\n",
           (unsigned long long)cyc, (unsigned long long)insn,
           cyc ? (double)insn / (double)cyc : 0.0, model->halt ? 1 : 0);
    printf("#STATS icm=%u dcm=%u mst=%u st=%u br=%u mis=%u\n",
           model->stat_icm, model->stat_dcm, model->mst_cnt, model->st_cnt,
           model->bp_branches, model->bp_mispreds);
    model->final();
    return model->halt ? 0 : 1;
}
