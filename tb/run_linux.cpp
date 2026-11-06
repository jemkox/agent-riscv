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
#endif

static const uint32_t KERNEL_ADDR = 0x80000000u;
static const uint32_t INITRD_ADDR = 0x82000000u;

#include "linux_runner_load.inc"

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
    std::vector<uint32_t> initrd;
    const char *initrd_path = getenv("LINUX_INITRD");
    if (initrd_path && *initrd_path) {
        if (!load_bin(initrd_path, initrd)) { printf("cannot read %s\n", initrd_path); return 1; }
    }
    const uint64_t max_cycles = (argc > 3) ? strtoull(argv[3], nullptr, 10) : 1200000000ull;
    const bool prompt_stop = (argc > 4) && !std::strcmp(argv[4], "prompt");
    const bool platform_stop = (argc > 4) && !std::strcmp(argv[4], "platform");
    const bool shell_stop = (argc > 4) && !std::strcmp(argv[4], "shell");
#ifdef LINUX_CKPT
#include "linux_ckpt_config.inc"
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
        if (!initrd.empty()) load_words(INITRD_ADDR, initrd);

        setc(1, 1, 0, 0, 0, 0, 0); model->eval();
        setc(0, 0, 0, 0, 0, 0, 0); model->eval();
    }

    uint64_t cyc = 0, insns = 0;
    std::string tail;
    struct TraceEntry { uint32_t pc, insn, rd, wv, ea; };
    std::deque<TraceEntry> trace;
    std::deque<std::array<uint32_t, 3>> store_ring;
    bool prompt_seen = false, done_seen = false, platform_seen = false;
    bool login_ready = false;
    bool cmd_uname_seen = false, cmd_cpuinfo_seen = false;
    uint32_t watch_addr = 0, watch_val = 0;
    std::deque<unsigned char> uart_input;
    bool login_prompt_seen = false, login_sent = false, commands_sent = false, done_sent = false;
    bool password_sent = false, login_failed_seen = false;
    uint64_t login_prompt_cyc = 0;
    bool uname_ok = false, cpuinfo_ok = false, ls_ok = false;
    auto queue_text = [&](const std::string &s) {
        printf("#QUEUE len=%zu text=%s\n", s.size(), s.c_str());
        for (unsigned char c : s) uart_input.push_back(c);
    };
    auto last_pos = [&](const std::string &s) {
        size_t p = std::string::npos;
        for (size_t i = 0; i + s.size() <= tail.size(); ++i)
            if (tail.compare(i, s.size(), s) == 0) p = i;
        return p;
    };
    auto saw_after = [&](const std::string &cmd, const std::string &out) {
        size_t p = last_pos(cmd);
        return p != std::string::npos && tail.find(out, p + cmd.size()) != std::string::npos;
    };
#ifdef LINUX_DEBUG
#include "linux_debug_init.inc"
#endif
#include "linux_runner_feed.inc"
#include "linux_runner_gates.inc"

#ifdef LINUX_CKPT
#include "linux_ckpt_restore.inc"
#endif

    while (cyc < max_cycles) {
#ifdef LINUX_CKPT
#include "linux_ckpt_save.inc"
#endif
        if (login_prompt_seen && login_prompt_cyc != 0 && !login_sent &&
            cyc >= login_prompt_cyc + 5000000ull && uart_input.empty()) {
            queue_text("root\n");
            login_sent = true;
            password_sent = false;
        }
        bool up_ready = (!model->uart_rx_pending && !uart_input.empty());
        uint32_t up_rx = up_ready ? uart_input.front() : 0u;
        bool pending_false = !model->uart_rx_pending;
        setc(1, 0, 0, 0, 0, up_ready ? 1u : 0u, up_rx);
        model->eval();
        bool load_up = ((model->ex_insn & 0x7fu) == 0x03u) &&
                       (model->ex_ea == 0x10000000u);
        if (up_ready && (model->uart_rx_pending ||
                         (pending_false && load_up))) {
            printf("#STDIN_UP cyc=%llu ch=%02x ascii=%c\n",
                   (unsigned long long)cyc, (unsigned)up_rx,
                   (up_rx >= 32u && up_rx < 127u) ? (char)up_rx : '.');
            uart_input.pop_front();
        }
        // process only after the down-clock state below; otherwise UART stores/retires duplicate

        bool down_ready = (!model->uart_rx_pending && !uart_input.empty());
        uint32_t down_rx = down_ready ? uart_input.front() : 0u;
        pending_false = !model->uart_rx_pending;
        setc(0, 0, 0, 0, 0, down_ready ? 1u : 0u, down_rx);
        model->eval();
        bool load_down = ((model->ex_insn & 0x7fu) == 0x03u) &&
                         (model->ex_ea == 0x10000000u);
        if (down_ready && (model->uart_rx_pending ||
                           (pending_false && load_down))) {
            printf("#STDIN cyc=%llu ch=%02x ascii=%c\n",
                   (unsigned long long)cyc, (unsigned)down_rx,
                   (down_rx >= 32u && down_rx < 127u) ? (char)down_rx : '.');
            uart_input.pop_front();
        }
        if (model->rv_valid) {
            insns++;
            if (model->ex_ea == 0x10000000u || model->ex_ea == 0x10000005u) {
                static uint32_t uart_dev_seen = 0;
                if (uart_dev_seen < 3000u) {
                    ++uart_dev_seen;
                    bool is_load = !model->ex_st;
                    uint32_t ch = model->ex_wv & 0xffu;
                    printf("#UART_DEV cyc=%llu pc=%08x ea=%08x st=%u load=%u rd=%u wv=%08x sa=%08x wben=%u\n",
                           (unsigned long long)cyc, (unsigned)model->ex_pc,
                           (unsigned)model->ex_ea, (unsigned)model->ex_st,
                           (unsigned)is_load, (unsigned)model->ex_rd,
                           (unsigned)model->ex_wv, (unsigned)model->ex_sa,
                           (unsigned)model->ex_wben);
                    if (is_load && model->ex_ea == 0x10000000u && ch >= 32u && ch < 127u)
                        printf("#UART_CH cyc=%llu ch=%02x ascii=%c\n",
                               (unsigned long long)cyc, ch, (char)ch);
                }
            }
#ifdef LINUX_DEBUG
            if (rtf) {
                uint32_t rec[8] = {(uint32_t)cyc, (uint32_t)model->ex_pc,
                                   (uint32_t)model->ex_insn, (uint32_t)model->ex_rd,
                                   (uint32_t)model->ex_wv, (uint32_t)(model->ex_st ? 1 : 0),
                                   (uint32_t)model->ex_ea, (uint32_t)model->ex_sd};
                fwrite(rec, sizeof(rec), 1, rtf);
            }
#endif
            trace.push_back({model->ex_pc, model->ex_insn, model->ex_rd, model->ex_wv,
                             model->ex_ea});
            if (trace.size() > 200) trace.pop_front();
            if (model->ex_st) {
                store_ring.push_back({model->ex_pc, model->ex_ea, model->ex_sd});
                if (store_ring.size() > 400) store_ring.pop_front();
#ifdef LINUX_DEBUG
                static uint32_t uart_store_seen = 0;
                if (model->ex_ea == 0x10000000u) {
                    ++uart_store_seen;
                    if (dbg_log)
                        std::fprintf(dbg_log, "#UART_ST cyc=%llu pc=%08x insn=%08x ea=%08x sd=%08x\n",
                                     (unsigned long long)cyc, (unsigned)model->ex_pc,
                                     (unsigned)model->ex_insn, (unsigned)model->ex_ea,
                                     (unsigned)model->ex_sd);
                }
#endif
            }
#ifdef LINUX_DEBUG
#include "linux_debug_markers.inc"
#endif
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
#ifdef LINUX_DEBUG
#include "linux_debug_snap.inc"
#endif
        if (done_seen || (prompt_stop && prompt_seen) ||
            (platform_stop && platform_seen) || model->halt) {
            if (platform_stop && platform_seen)
                printf("#STOP platform cyc=%llu\n", (unsigned long long)cyc);
            break;
        }
        cyc++;
    }

#ifdef LINUX_DEBUG
#include "linux_debug_close.inc"
#endif
    if (!done_seen && !prompt_seen) {
        printf("#TAIL %zu bytes\n", tail.size());
        for (char ch : tail) putchar((unsigned char)ch);
        printf("\n");
        for (auto t : trace) printf("#TRACE %08x %08x %u %08x %08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
    }
    printf("#LINUX cycles=%llu insns=%llu prompt=%d login=%d done=%d halt=%d cmds=%d dtb=%08x\n",
           (unsigned long long)cyc, (unsigned long long)insns,
           prompt_seen ? 1 : 0, login_ready ? 1 : 0, done_seen ? 1 : 0,
           model->halt ? 1 : 0,
           (uname_ok && cpuinfo_ok && ls_ok) ? 1 : 0, dtb_addr);
    printf("#BP bp=%u taken=%u mis=%u\n",
           model->bp_branches, model->bp_taken_preds, model->bp_mispreds);
    model->final();
    return done_seen ? 0 :
           (prompt_stop ? (prompt_seen ? 0 : 1) :
            (platform_stop ? (platform_seen ? 0 : 1) : 1));
}
