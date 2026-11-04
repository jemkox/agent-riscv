// Linux Sim runner: loads RV32 Linux raw binary at 0x80000000, the DTB after it,
// a tiny jump stub at 0, and drives UART MMIO at 0x10000000.
// Usage: run_linux <vmlinux.bin> <linux.dtb> [max_cycles] [prompt]
#include <verilated.h>
#include <memory>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <deque>
#include <array>
#include <unistd.h>
#include <cerrno>
#include "Vrun_linux.h"

static const uint32_t KERNEL_ADDR = 0x80000000u;

static bool load_bin(const char *path, std::vector<uint32_t> &out) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return false; }
    out.resize((size_t)((sz + 3) / 4));
    for (size_t i = 0; i < out.size(); i++) {
        uint32_t w = 0;
        unsigned char b[4] = {0,0,0,0};
        size_t n = fread(b, 1, 4, f);
        if (n != 4 && feof(f)) {
            for (size_t k=0;k<n;k++) w |= ((uint32_t)b[k]) << (8*k);
            out[i] = w;
        } else if (n == 4) {
            out[i] = (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
                     ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
        } else {
            fclose(f); return false;
        }
    }
    fclose(f);
    return true;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("usage: run_linux <vmlinux.bin> <linux.dtb> [max_cycles] [prompt]\n");
        return 2;
    }
    Verilated::commandArgs(argc, argv);
    std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    std::unique_ptr<Vrun_linux> model{new Vrun_linux(contextp.get())};

    std::vector<uint32_t> kernel, dtb;
    if (!load_bin(argv[1], kernel)) { printf("cannot read %s\n", argv[1]); return 1; }
    if (!load_bin(argv[2], dtb)) { printf("cannot read %s\n", argv[2]); return 1; }
    const uint64_t max_cycles = (argc > 3) ? strtoull(argv[3], nullptr, 10) : 1200000000ull;
    const bool prompt_stop = (argc > 4) && !std::strcmp(argv[4], "prompt");
    const bool platform_stop = (argc > 4) && !std::strcmp(argv[4], "platform");

    uint32_t kernel_bytes = (uint32_t)(kernel.size() * 4u);
    uint32_t pad = (kernel_bytes + 0xFFFu) & ~0xFFFu;
    uint32_t dtb_addr = KERNEL_ADDR + 0x3e00000u; // mimic qemu virt DTB near top of 64M block

    auto setc = [&](uint32_t clk, uint32_t reset, uint32_t lwe, uint32_t lwa,
                    uint32_t lwd, uint32_t rx_ready, uint32_t rx_in) {
        model->clk = clk;
        model->reset = reset;
        model->lwe = lwe;
        model->lwa = lwa;
        model->lwd = lwd;
        model->linux_dtb_addr = dtb_addr;
        model->uart_rx_ready = rx_ready;
        model->uart_rx_in = (uint8_t)rx_in;
    };

    auto load_words = [&](uint32_t base, const std::vector<uint32_t> &w) {
        for (size_t i = 0; i < w.size(); i++) {
            if (!w[i]) continue;
            uint32_t addr = base + (uint32_t)i * 4u;
            setc(1, 1, 1, addr, w[i], 0, 0); model->eval();
            setc(0, 1, 1, addr, w[i], 0, 0); model->eval();
        }
    };

    setc(0, 1, 0, 0, 0, 0, 0); model->eval();
    load_words(KERNEL_ADDR, kernel);
    load_words(dtb_addr, dtb);

    setc(1, 1, 0, 0, 0, 0, 0); model->eval();
    setc(0, 0, 0, 0, 0, 0, 0); model->eval();

    uint64_t cyc = 0, insns = 0;
    std::string tail;
    struct TraceEntry { uint32_t pc, insn, rd, wv, ea; };
    std::deque<TraceEntry> trace;
    std::deque<std::array<uint32_t, 3>> store_ring;
    bool prompt_seen = false, done_seen = false, platform_seen = false;
    uint32_t watch_addr = 0, watch_val = 0;
    auto feed_output = [&](uint32_t ch) {
        std::putchar((char)ch);
        std::fflush(stdout);
        tail.push_back((char)ch);
        if (tail.size() > 8192) tail.erase(0, tail.size() - 8192);
        if (tail.find("LINUX_SIM_DONE") != std::string::npos) done_seen = true;
        if (tail.find("~ #") != std::string::npos || tail.find("~ $") != std::string::npos)
            prompt_seen = true;
    };

    struct Gate { std::string name; uint32_t pc; bool seen; };
    std::vector<Gate> gates;
    {
        FILE *gf = fopen("linux/gate.txt", "r");
        if (gf) {
            char nm[64];
            unsigned long long pcv;
            while (fscanf(gf, "%63s %llx", nm, &pcv) == 2)
                gates.push_back({nm, (uint32_t)pcv, false});
            fclose(gf);
        }
    }
    auto gate_seen = [&](const char *name) {
        for (const auto &g : gates)
            if (g.name == name) return g.seen;
        return false;
    };

    while (cyc < max_cycles) {
        uint32_t rx_ready = 0, rx_byte = 0;
        if (!model->uart_rx_pending) {
            unsigned char ch = 0;
            ssize_t n = read(0, &ch, 1);
            if (n == 1) { rx_ready = 1; rx_byte = ch; }
        }
        setc(1, 0, 0, 0, 0, rx_ready, rx_byte);
        model->eval();
        // process only after the down-clock state below; otherwise UART stores/retires duplicate

        rx_ready = 0; rx_byte = 0;
        if (!model->uart_rx_pending) {
            unsigned char ch = 0;
            ssize_t n = read(0, &ch, 1);
            if (n == 1) { rx_ready = 1; rx_byte = ch; }
        }
        setc(0, 0, 0, 0, 0, rx_ready, rx_byte);
        model->eval();
        if (model->rv_valid) {
            insns++;
            trace.push_back({model->ex_pc, model->ex_insn, model->ex_rd, model->ex_wv,
                             model->ex_ea});
            if (trace.size() > 200) trace.pop_front();
            if (model->ex_st) {
                store_ring.push_back({model->ex_pc, model->ex_ea, model->ex_sd});
                if (store_ring.size() > 400) store_ring.pop_front();
            }
            {
                uint32_t p = model->ex_pc;
                if (p == 0x8045ef8cu || p == 0x8045f08cu) {
                    printf("#VSN_BASE cyc=%llu pc=%08x ea=%08x val=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_wv);
                }
                if (p == 0x8045ef90u) {
                    printf("#VSN_CAN_ST cyc=%llu pc=%08x ea=%08x val=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_sd);
                    watch_addr = model->ex_ea;
                    watch_val = model->ex_sd;
                }
                if (watch_addr && model->ex_st && model->ex_ea == watch_addr) {
                    printf("#WATCH_ST cyc=%llu pc=%08x ea=%08x val=%08x expected=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_sd,
                           (unsigned)watch_val);
                }
                if (p == 0x8045f088u) {
                    printf("#VSN_CAN_LD cyc=%llu pc=%08x ea=%08x val=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_wv);
                    if (model->ex_ea == watch_addr && model->ex_wv != watch_val) {
                        printf("#WATCH_BAD_LD cyc=%llu pc=%08x ea=%08x got=%08x expected=%08x\n",
                               (unsigned long long)cyc, (unsigned)p,
                               (unsigned)model->ex_ea, (unsigned)model->ex_wv,
                               (unsigned)watch_val);
                    }
                    watch_addr = 0;
                    watch_val = 0;
                }
                if (p == 0x8045f090u && model->ex_wv != 0) {
                    printf("#VSN_MISMATCH cyc=%llu xor=%08x\n",
                           (unsigned long long)cyc, (unsigned)model->ex_wv);
                }
                if (p == 0x80473ef4u) {
                    printf("#VSN_SC cyc=%llu pc=%08x ea=%08x val=%08x ok=%u\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_sd,
                           (unsigned)(model->ex_rd == 0 ? 1u : 1u));
                }
                if (p == 0x80473dc0u || p == 0x80473dc4u) {
                    printf("#HND_SP_ST cyc=%llu pc=%08x ea=%08x val=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_sd);
                }
                if (p == 0x80473dc8u) {
                    printf("#HND_SP_LD cyc=%llu pc=%08x ea=%08x val=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_ea, (unsigned)model->ex_wv);
                }
            }
        }
        if (model->uart_tx_valid) feed_output(model->uart_tx_out & 0xFFu);
        {
            uint32_t epc = model->ex_pc;
            for (auto &g : gates) {
                if (epc == g.pc && !g.seen) {
                    g.seen = true;
                    if (g.name == "__stack_chk_fail") {
                        printf("#STACK_CHK_FAIL pc=%08x cyc=%llu stores=%u\n",
                               (unsigned)epc, (unsigned long long)cyc,
                               (unsigned)store_ring.size());
                        for (const auto &s : store_ring)
                            printf("#STORE pc=%08x ea=%08x sd=%08x\n",
                                   s[0], s[1], s[2]);
                    }
                    printf("#GATE %s cyc=%llu pc=%08x\n",
                           g.name.c_str(), (unsigned long long)cyc, (unsigned)epc);
                    for (auto t : trace)
                        printf("#EVT %08x %08x %u %08x %08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
                }
            }
            if (platform_stop && gate_seen("kernel_init_freeable")) platform_seen = true;
        }
        if (trace.size() == 200 && cyc && (cyc % 5000000u == 0u)) {
            printf("#SNAP cycles=%llu\n", (unsigned long long)cyc);
            for (auto t : trace) printf("#TRACE %08x %08x %u %08x %08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
        }
        if (done_seen || (prompt_stop && prompt_seen) ||
            (platform_stop && platform_seen) || model->halt) {
            if (platform_stop && platform_seen)
                printf("#STOP platform cyc=%llu\n", (unsigned long long)cyc);
            break;
        }
        cyc++;
    }

    if (!done_seen && !prompt_seen) {
        printf("#TAIL %zu bytes\n", tail.size());
        for (char ch : tail) putchar((unsigned char)ch);
        printf("\n");
        for (auto t : trace) printf("#TRACE %08x %08x %u %08x %08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
    }
    printf("#LINUX cycles=%llu insns=%llu prompt=%d done=%d halt=%d dtb=%08x\n",
           (unsigned long long)cyc, (unsigned long long)insns,
           prompt_seen ? 1 : 0, done_seen ? 1 : 0, model->halt ? 1 : 0, dtb_addr);
    printf("#BP bp=%u taken=%u mis=%u\n",
           model->bp_branches, model->bp_taken_preds, model->bp_mispreds);
    model->final();
    return done_seen ? 0 :
           (prompt_stop ? (prompt_seen ? 0 : 1) :
            (platform_stop ? (platform_seen ? 0 : 1) : 1));
}
