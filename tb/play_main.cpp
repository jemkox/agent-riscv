// M10f `hdl make play` harness: Verilated Doom + SDL2 window (3x 320x200) and
// a key FIFO fed to the CPU through the cache32 KEY_ADDR MMIO load (key_in /
// key_hit). PLAY_SCRIPT env runs the same CPU headless with a scripted key
// sequence and saves PPM frames (verification without a window).
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <deque>
#include <memory>
#include "verilated.h"
#include "Vrun_doom.h"
#include "Vrun_doom___024root.h"
#include <SDL2/SDL.h>

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
static uint32_t mapScript(const char *t) {
    if (!strcmp(t, "enter")) return 13;
    if (!strcmp(t, "esc")) return 27;
    if (!strcmp(t, "up")) return 0xad;
    if (!strcmp(t, "down")) return 0xaf;
    if (!strcmp(t, "left")) return 0xac;
    if (!strcmp(t, "right")) return 0xae;
    if (!strcmp(t, "fire")) return 0xa3;
    if (!strcmp(t, "use")) return 0xa2;
    if (strlen(t) == 1) return (uint32_t)(unsigned char)t[0];
    return 0;
}
static uint32_t mapSym(Sint32 k) {
    switch (k) {
    case SDLK_UP: return 0xad;
    case SDLK_DOWN: return 0xaf;
    case SDLK_LEFT: return 0xac;
    case SDLK_RIGHT: return 0xae;
    case SDLK_LCTRL: case SDLK_RCTRL: return 0xa3;
    case SDLK_SPACE: return 0xa2;
    case SDLK_RETURN: return 13;
    case SDLK_ESCAPE: return 27;
    default: if (k > 0 && k < 128) return (uint32_t)k; return 0;
    }
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const char *script = getenv("PLAY_SCRIPT");
    uint64_t max_cycles = (argc > 1) ? atoll(argv[1]) : 100000000ull;
    const int FB_W = 320, FB_H = 200;

    std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    std::unique_ptr<Vrun_doom> model{new Vrun_doom(contextp.get())};
    std::vector<uint32_t> prog, wad;
    if (!load_hex("build/doom/doom.hex", prog) ||
        !load_hex("build/doom/wad.hex", wad)) {
        printf("doom/wad hex missing\n"); return 1;
    }
    uint32_t fb_sym = lookup_sym("build/doom/doom.syms", "DG_ScreenBuffer");
    const uint32_t FRAME_ADDR = 0x1FF00004u, UART_ADDR = 0x1FF00000u,
                   WAD_ADDR = 0x00C00000u;
    auto setc = [&](uint32_t clk, uint32_t reset) {
        model->clk = clk; model->reset = reset;
    };
    setc(0, 1);
    model->eval();
    uint64_t cyc = 0;
    auto load_words = [&](const std::vector<uint32_t> &blob, uint32_t base) {
        for (size_t i = 0; i < blob.size(); i++) {
            if (!blob[i]) continue;
            model->lwe = 1;
            model->lwa = base + 4u * (uint32_t)i;
            model->lwd = blob[i];
            model->clk = 1;
            model->eval();
            model->clk = 0;
            model->eval();
            cyc++;
        }
        model->lwe = 0;
    };
    load_words(prog, 0);
    load_words(wad, WAD_ADDR);

    auto read_word = [&](uint32_t addr) -> uint32_t {
        auto &rww = model->rootp->run_doom__DOT__T__DOT__MM__DOT__rw;
        uint32_t w = (addr >> 2) & 0x7FFFFFu, s = (addr & 3) * 8;
        if (!s) return rww[w];
        return (rww[w] >> s) | (rww[(w + 1) & 0x7FFFFFu] << (32 - s));
    };

    std::vector<std::pair<uint64_t, uint32_t>> sched;
    uint64_t tcur = 2000000;
    if (script) {
        std::string s(script);
        size_t pos = 0;
        while (pos < s.size()) {
            size_t c = s.find(',', pos);
            std::string tok = s.substr(pos, (c == std::string::npos) ? c : c - pos);
            pos = (c == std::string::npos) ? s.size() : c + 1;
            if (tok.empty()) continue;
            if (tok[0] == '@') { tcur += atoll(tok.c_str() + 1); continue; }
            uint64_t hold = 300000;
            std::string name = tok;
            size_t col = tok.find(':');
            if (col != std::string::npos) {
                name = tok.substr(0, col);
                hold = atoll((tok.substr(col + 1) + "0").c_str());
            }
            uint32_t k = mapScript(name.c_str());
            if (!k) continue;
            sched.push_back({tcur, (1u << 16) | k});
            tcur += hold;
            sched.push_back({tcur, k});
            tcur += 100000;
        }
    }
    size_t si = 0;
    std::deque<uint32_t> fifo;

    bool headless = script != nullptr;
    SDL_Window *win = nullptr;
    SDL_Surface *scr = nullptr;
    Uint32 pitchw = 0;
    if (!headless) {
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            printf("SDL init failed: %s\n", SDL_GetError());
            return 1;
        }
        win = SDL_CreateWindow("DOOM on rv32", SDL_WINDOWPOS_CENTERED,
                               SDL_WINDOWPOS_CENTERED, FB_W * 3, FB_H * 3, 0);
        if (!win) {
            printf("window creation failed: %s\n", SDL_GetError());
            return 1;
        }
        scr = SDL_GetWindowSurface(win);
        pitchw = scr->pitch / scr->format->BytesPerPixel;
    }

    FILE *log = fopen("build/play/logs/run.out", "w");
    bool done = false;
    uint64_t frames = 0;
    while (!done && cyc < max_cycles) {
        while (si < sched.size() && sched[si].first <= cyc) {
            fifo.push_back(sched[si].second);
            si++;
        }
        if (!headless) {
            SDL_Event e;
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) { done = true; break; }
                if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) {
                    uint32_t k = mapSym(e.key.keysym.sym);
                    if (k)
                        fifo.push_back(((e.type == SDL_KEYDOWN) ? (1u << 16) : 0u) | k);
                }
            }
            if (done) break;
        }
        model->key_in = fifo.empty() ? 0 : fifo.front();
        model->eval();
        // key_hit is combinational on the load now in EX, which captures key_in at THIS edge:
        // sample it before the edge (after the edge it describes the next instruction, and
        // popping then dropped every key-press, leaving only releases).
        const bool key_taken = model->key_hit;
        setc(1, 0);
        model->eval();
        if (key_taken && !fifo.empty()) fifo.pop_front();
        if (model->ex_st && model->ex_sa == UART_ADDR && (model->ex_sbe & 1))
            if (log) fprintf(log, "%c", (char)(model->ex_sd & 0xFF));
        if (model->ex_st && model->ex_sa == FRAME_ADDR) {
            uint32_t fb = read_word(fb_sym);
            char p[96];
            snprintf(p, sizeof p, "build/play/frames/frame_%03llu.ppm",
                     (unsigned long long)frames);
            FILE *ppm = fopen(p, "w");
            std::vector<uint32_t> pix(FB_W * FB_H);
            if (fb) {
                for (int y = 0; y < FB_H; y++)
                    for (int x = 0; x < FB_W; x++)
                        pix[y * FB_W + x] = read_word(fb + 4u * (y * FB_W + x));
            }
            if (ppm && fb) {
                fprintf(ppm, "P6\n%d %d\n255\n", FB_W, FB_H);
                for (int i = 0; i < FB_W * FB_H; i++) {
                    unsigned char b[3] = {(unsigned char)((pix[i] >> 16) & 0xFF),
                                          (unsigned char)((pix[i] >> 8) & 0xFF),
                                          (unsigned char)(pix[i] & 0xFF)};
                    fwrite(b, 1, 3, ppm);
                }
                fclose(ppm);
            }
            if (!headless && fb) {
                Uint32 *sp = (Uint32 *)scr->pixels;
                for (int y = 0; y < FB_H; y++) {
                    for (int x = 0; x < FB_W; x++) {
                        uint32_t c = pix[y * FB_W + x];
                        Uint32 col = SDL_MapRGBA(scr->format, (c >> 16) & 0xFF,
                                                 (c >> 8) & 0xFF, c & 0xFF, 0xFF);
                        for (int dy = 0; dy < 3; dy++)
                            for (int dx = 0; dx < 3; dx++)
                                sp[(uint32_t)(y * 3 + dy) * pitchw + (uint32_t)(x * 3 + dx)] = col;
                    }
                }
                SDL_UpdateWindowSurface(win);
            }
            frames++;
            if (log) fprintf(log, "#frame=%llu cyc=%llu\n",
                             (unsigned long long)frames,
                             (unsigned long long)cyc);
        }
        if (model->halt) done = true;
        setc(0, 0);
        model->eval();
        cyc++;
        if ((cyc & 0xFFFFF) == 0 && log) fflush(log);
    }
    if (log) {
        fprintf(log, "#RUN cycles=%llu frames=%llu halt=%d\n",
                (unsigned long long)cyc, (unsigned long long)frames,
                model->halt ? 1 : 0);
        fclose(log);
    }
    printf("play: cycles=%llu frames=%llu headless=%d\n",
           (unsigned long long)cyc, (unsigned long long)frames, headless ? 1 : 0);
    if (!headless) {
        SDL_DestroyWindow(win);
        SDL_Quit();
    }
    return 0;
}
