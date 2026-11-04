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
#ifdef LINUX_CKPT
#include <verilated_save.h>
#include <vector>
#include <deque>
#include <array>
#endif

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
#ifdef LINUX_CKPT
    const bool ckpt_save = (argc > 5) && !std::strcmp(argv[5], "save");
    const bool ckpt_restore = (argc > 5) && !std::strcmp(argv[5], "restore");
    const bool ckpt_mark = (argc > 5) && !std::strcmp(argv[5], "mark");
    const uint64_t mark_cycle = (ckpt_mark && argc > 6) ? strtoull(argv[6], nullptr, 10) : 0ull;
    const uint64_t save_cycle = (ckpt_save && max_cycles > 0) ? (max_cycles - 1) : 0ull;
    const std::string ckpt_file = (argc > 6 && (ckpt_save || ckpt_restore)) ? std::string(argv[6]) : std::string();
    const std::string ckpt_hash_arg = (argc > 7 && (ckpt_save || ckpt_restore)) ? std::string(argv[7]) : std::string();
#endif

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

#ifdef LINUX_CKPT
    if (!ckpt_restore) {
#else
    {
#endif
        setc(0, 1, 0, 0, 0, 0, 0); model->eval();
        load_words(KERNEL_ADDR, kernel);
        load_words(dtb_addr, dtb);

        setc(1, 1, 0, 0, 0, 0, 0); model->eval();
        setc(0, 0, 0, 0, 0, 0, 0); model->eval();
    }

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

#ifdef LINUX_CKPT
    auto print_state = [&](const char *tag) {
        printf("#CKPT_%s cyc=%llu insns=%llu pc=%08x insn=%08x rd=%u wv=%08x st=%u ea=%08x halt=%u prompt=%u done=%u platform=%u\n",
               tag, (unsigned long long)cyc, (unsigned long long)insns,
               (unsigned)model->ex_pc, (unsigned)model->ex_insn,
               (unsigned)model->ex_rd, (unsigned)model->ex_wv,
               (unsigned)model->ex_st, (unsigned)model->ex_ea,
               (unsigned)model->halt, prompt_seen ? 1u : 0u,
               done_seen ? 1u : 0u, platform_seen ? 1u : 0u);
    };

    if (ckpt_restore) {
        if (ckpt_file.empty()) {
            printf("#CKPT_FAIL usage: restore <file> <hash>\n");
            return 3;
        }
        VerilatedRestore os;
        os.open(ckpt_file.c_str());
        if (!os.isOpen()) {
            printf("#CKPT_FAIL cannot open %s\n", ckpt_file.c_str());
            return 1;
        }
        std::string h;
        os >> h;
        if (h != ckpt_hash_arg) {
            printf("#CKPT_REFUSE hash mismatch: file=%s snapshot=%s expected=%s\n",
                   ckpt_file.c_str(), h.c_str(), ckpt_hash_arg.c_str());
            exit(3);
        }
        os >> cyc;
        os >> insns;
        os >> prompt_seen;
        os >> done_seen;
        os >> platform_seen;
        os >> watch_addr;
        os >> watch_val;
        uint32_t gate_count = 0;
        os >> gate_count;
        if (gate_count != (uint32_t)gates.size()) {
            printf("#CKPT_REFUSE gate count mismatch: file=%u snapshot=%u\n",
                   (unsigned)gates.size(), (unsigned)gate_count);
            exit(3);
        }
        for (auto &g : gates) os >> g.seen;
        uint32_t trace_count = 0;
        os >> trace_count;
        for (uint32_t i = 0; i < trace_count; i++) {
            TraceEntry e;
            os >> e.pc; os >> e.insn; os >> e.rd; os >> e.wv; os >> e.ea;
            trace.push_back(e);
        }
        uint32_t store_count = 0;
        os >> store_count;
        for (uint32_t i = 0; i < store_count; i++) {
            std::array<uint32_t, 3> s;
            os >> s[0]; os >> s[1]; os >> s[2];
            store_ring.push_back(s);
        }
        os >> tail;
        os >> contextp.get();
        os >> *model;
        if (!os.isOpen()) {
            printf("#CKPT_FAIL restore stream closed before model: %s\n", ckpt_file.c_str());
            exit(1);
        }
        os.close();
        print_state("RESTORE");
    }
#endif

    while (cyc < max_cycles) {
#ifdef LINUX_CKPT
        if (ckpt_mark && cyc == mark_cycle) print_state("MARK");
        if (ckpt_save && cyc == save_cycle) {
            printf("#CKPT_SAVE cyc=%llu insns=%llu file=%s hash=%s\n",
                   (unsigned long long)cyc, (unsigned long long)insns,
                   ckpt_file.c_str(), ckpt_hash_arg.c_str());
            print_state("SAVE");
            VerilatedSave os;
            os.open(ckpt_file.c_str());
            if (!os.isOpen()) {
                printf("#CKPT_FAIL cannot create %s\n", ckpt_file.c_str());
                return 1;
            }
            os << ckpt_hash_arg;
            os << (uint64_t)cyc;
            os << (uint64_t)insns;
            os << prompt_seen;
            os << done_seen;
            os << platform_seen;
            os << watch_addr;
            os << watch_val;
            os << (uint32_t)gates.size();
            for (const auto &g : gates) os << g.seen;
            os << (uint32_t)trace.size();
            for (const auto &t : trace) {
                os << (uint32_t)t.pc; os << (uint32_t)t.insn;
                os << (uint32_t)t.rd; os << (uint32_t)t.wv;
                os << (uint32_t)t.ea;
            }
            os << (uint32_t)store_ring.size();
            for (const auto &s : store_ring) {
                os << (uint32_t)s[0]; os << (uint32_t)s[1];
                os << (uint32_t)s[2];
            }
            os << tail;
            os << contextp.get();
            os << *model;
            if (!os.isOpen()) {
                printf("#CKPT_FAIL save stream closed: %s\n", ckpt_file.c_str());
                os.close();
                return 1;
            }
            os.close();
            model->final();
            return 0;
        }
#endif
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
                   (unsigned)(model->ex_rd == 0 ? 1u : 0u));
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
