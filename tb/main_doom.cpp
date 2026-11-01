// P2 fast Doom runner: C++ clock loop, direct RAM readback via dbg port.
#include <verilated.h>
#include <memory>
#include "Vrun_doom.h"
#include "Vrun_doom___024root.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <cstdlib>

static bool load_hex(const char *path, std::vector<uint32_t> &out) {
    FILE *f = fopen(path, "r");
    if (!f) return false;
    unsigned v;
    while (fscanf(f, "%x", &v) == 1) out.push_back(v);
    fclose(f);
    return true;
}

static uint32_t lookup_sym(const char *path, const char *name) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char line[256];
    while (fgets(line, sizeof line, f)) {
        uint32_t a; char t, n[128];
        if (sscanf(line, "%x %c %127s", &a, &t, n) == 3)
            if (strcmp(n, name) == 0) { fclose(f); return a; }
    }
    fclose(f);
    return 0;
}

static std::string frame_path(int i) {
    char buf[96];
    snprintf(buf, sizeof buf, "build/doom/frames/frame_%03d.ppm", i);
    return std::string(buf);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    std::unique_ptr<Vrun_doom> model{new Vrun_doom(contextp.get())};

    std::vector<uint32_t> prog, wad;
    if (!load_hex("build/doom/doom.hex", prog)) {
        printf("doom hex missing\n"); return 1;
    }
    if (!load_hex("build/doom/wad.hex", wad)) {
        printf("wad hex missing\n"); return 1;
    }
    uint32_t fb_sym = lookup_sym("build/doom/doom.syms", "DG_ScreenBuffer");
    printf("sym DG_ScreenBuffer = %08x\n", fb_sym);

    const uint32_t FRAME_ADDR = 0x1FF00004u;
    const uint32_t UART_ADDR  = 0x1FF00000u;
    const uint32_t WAD_ADDR   = 0x00C00000u;
    const int FB_W = 320, FB_H = 200;

    auto setc = [&](uint32_t clk, uint32_t reset, uint32_t lwe,
                    uint32_t lwa, uint32_t lwd, uint32_t dbg_re,
                    uint32_t dbg_ra) {
        model->clk = clk; model->reset = reset;
        model->lwe = lwe; model->lwa = lwa; model->lwd = lwd;
        model->dbg_re = dbg_re; model->dbg_ra = dbg_ra;
    };

    setc(0, 1, 0, 0, 0, 0, 0);
    model->eval();
    uint64_t cyc = 0;
    auto step = [&]() {
        setc(1, 1, 0, 0, 0, 0, 0); model->eval();
        setc(0, 1, 0, 0, 0, 0, 0); model->eval();
        cyc++;
    };

    auto load_words = [&](const std::vector<uint32_t> &blob, uint32_t base) {
        for (size_t i = 0; i < blob.size(); i++) {
            if (!blob[i]) continue;
            setc(1, 1, 1, base + 4u * (uint32_t)i, blob[i], 0, 0);
            model->eval();
            setc(0, 1, 1, base + 4u * (uint32_t)i, blob[i], 0, 0);
            model->eval();
            cyc++;
        }
    };
    load_words(prog, 0);
    load_words(wad, WAD_ADDR);

    auto read_word = [&](uint32_t addr) -> uint32_t {
        auto &ram = model->rootp->run_doom__DOT__T__DOT__MM__DOT__ram;
        uint32_t m = addr & 0x1FFFFFFu;
        return ((uint32_t)ram[m] | ((uint32_t)ram[(m + 1) & 0x1FFFFFFu] << 8) |
                ((uint32_t)ram[(m + 2) & 0x1FFFFFFu] << 16) |
                ((uint32_t)ram[(m + 3) & 0x1FFFFFFu] << 24));
    };

    FILE *uartlog = fopen("build/doom/logs/run.out", "w");
    uint64_t insn = 0, frames = 0, last_frame_cyc = 0;
    const uint64_t max_cycles = (argc > 1) ? atoll(argv[1]) : 400000000ull;
    const int max_frames = 31;

    setc(0, 0, 0, 0, 0, 0, 0);
    model->eval();
    bool done = false;
    while (!done && cyc < max_cycles) {
        setc(1, 0, 0, 0, 0, 0, 0);
        model->eval();
        if (model->rv_valid) insn++;
        if (model->ex_st && model->ex_sa == UART_ADDR && (model->ex_sbe & 1)) {
            if (uartlog) fprintf(uartlog, "%c", (char)(model->ex_sd & 0xFF));
        }
        if (model->ex_st && model->ex_sa == FRAME_ADDR) {
            uint32_t fb = read_word(fb_sym);
            if (frames < (uint64_t)max_frames && fb && uartlog) {
                std::string p = frame_path((int)frames);
                FILE *ppm = fopen(p.c_str(), "w");
                if (ppm) {
                    fprintf(ppm, "P6\n%d %d\n255\n", FB_W, FB_H);
                    for (int y = 0; y < FB_H; y++) {
                        for (int x = 0; x < FB_W; x++) {
                            uint32_t px = read_word(fb + 4u*(y*FB_W + x));
                            unsigned char b[3] = {
                                (unsigned char)((px >> 16) & 0xFF), // R (red offset 16)
                                (unsigned char)((px >> 8) & 0xFF),  // G
                                (unsigned char)(px & 0xFF)};        // B (offset 0)
                            // framebuffer stores RGB5? cmap_to_fb writes byte order; keep 3 LSBs per pixel:
                            fwrite(b, 1, 3, ppm);
                        }
                    }
                    fclose(ppm);
                }
                if (uartlog) fprintf(uartlog, "#FRAME %llu at cycle %llu\n",
                                     (unsigned long long)frames,
                                     (unsigned long long)cyc);
            }
            if (frames > 0) {
                uint64_t d = cyc - last_frame_cyc;
                if (uartlog) fprintf(uartlog, "#frame=%llu cyc=%llu\n",
                                     (unsigned long long)frames,
                                     (unsigned long long)d);
            }
            last_frame_cyc = cyc;
            frames++;
            if (frames >= (uint64_t)max_frames) done = true;
        }
        if (model->halt) { done = true; }
        setc(0, 0, 0, 0, 0, 0, 0);
        model->eval();
        cyc++;
        if ((cyc & 0xFFFFF) == 0 && uartlog) fflush(uartlog);
    }
    if (uartlog) {
        fprintf(uartlog, "#RUN cycles=%llu insns=%llu frames=%llu halt=%d\n",
                (unsigned long long)cyc, (unsigned long long)insn,
                (unsigned long long)frames, model->halt ? 1 : 0);
        fclose(uartlog);
    }
    printf("cycles=%llu insns=%llu frames=%llu IPC=%.3f cyc/frame(last)=%llu\n",
           (unsigned long long)cyc, (unsigned long long)insn,
           (unsigned long long)frames,
           (cyc ? (double)insn / (double)cyc : 0.0),
           (unsigned long long)(frames ? last_frame_cyc : 0));
    // WAD sanity: magic, lump count, tail TOC
    uint32_t w0 = read_word(WAD_ADDR + 0), w4 = read_word(WAD_ADDR + 4);
    uint32_t e1 = read_word(WAD_ADDR + 4196020u - 4u);
    uint32_t e2 = read_word(WAD_ADDR + 4196020u - 8u);
    uint32_t e3 = read_word(WAD_ADDR + 4196020u - 12u);
    printf("WAD[0]=%08x WAD[4]=%d tail@-4=%08x tail@-8=%08x tail@-12=%08x\n",
           w0, w4, e1, e2, e3);
    model->final();
    return 0;
}
