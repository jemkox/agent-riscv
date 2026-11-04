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
    bool prompt_seen = false, done_seen = false, platform_seen = false;
    auto feed_output = [&](uint32_t ch) {
        std::putchar((char)ch);
        std::fflush(stdout);
        tail.push_back((char)ch);
        if (tail.size() > 512) tail.erase(0, tail.size() - 512);
        if (tail.find("LINUX_SIM_DONE") != std::string::npos) done_seen = true;
        if (tail.find("~ #") != std::string::npos || tail.find("~ $") != std::string::npos)
            prompt_seen = true;
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
        }
        if (model->uart_tx_valid) feed_output(model->uart_tx_out & 0xFFu);
        {
            uint32_t epc = model->ex_pc;
            static const uint32_t ev_pcs[] = {
                0x8046cf18u, 0x80001068u, 0x80476808u, 0x8047ba00u, 0x80032534u,
                0x80032564u, 0x80032384u, 0x80032274u, 0x80032358u, 0x80032134u,
                0x80041420u, 0x80041834u, 0x80041458u, 0x8046e900u, 0x80473290u,
                0x8046df7cu, 0x8046e18cu, 0x8003c95cu, 0x8046cedcu, 0x8046bbbcu,
                0x8046bbccu, 0x8046bbdcu, 0x80298cc4u, 0x80065234u, 0x800655bcu,
                0x80066094u, 0x800784f4u, 0x8047511cu, 0x804753d0u, 0x80475354u,
                0x804862d8u, 0x80475f50u, 0x804635e0u, 0x804636b8u, 0x800cd204u,
                0x80474b30u,                 0x8048dc08u, 0x80059a14u, 0x800d6fa8u, 0x800d7154u,
                0x8046cfc4u, 0x80002a74u, 0x80145cd8u, 0x804773ccu,
                0x804777fcu, 0x80476918u,                 0x8046cfecu, 0x8046d000u,
                0x8046d01cu, 0x804755b8u, 0x804755bcu, 0x804755c0u,
                0x8046d028u, 0x8046d030u, 0x8046d048u, 0x8046d04cu,
                0x8046d070u, 0x8046d07cu, 0x8046d0bcu, 0x804755b4u,
                0x80486314u, 0x80486334u, 0x80486340u, 0x80486348u,
                0x8046c9d4u, 0x8048634cu, 0x80486360u, 0x8047126cu,
                0x80470f78u, 0x80473ba0u, 0x800431c4u
            };
            static const uint32_t cnt_pcs[] = {
                0x8046bbccu, 0x8003c9d0u, 0x8003c99cu, 0x8046cedcu, 0x8046bbbcu,
                0x8046bbdcu, 0x80298cc4u, 0x80473290u, 0x8046df7cu, 0x8046e18cu,
                0x8046e900u, 0x80041be8u, 0x80032134u, 0x80032384u, 0x80041420u,
                0x80041834u, 0x80041458u, 0x80065234u, 0x800655bcu, 0x80066094u,
                static_cast<uint32_t>(0x80465fdc), 0x800d6fa8u, 0x800d7154u, 0x800d71b4u, 0x800d5f20u,
                0x800ee2b0u, 0x800d1418u, 0x800d1468u, 0x8010acc8u, 0x800d1b08u,
                0x80486310u, 0x80486324u, 0x804773ccu, 0x804777fcu,
                0x80476918u, 0x80486780u, 0x8048623cu, 0x800bd384u,
                0x8047126cu, 0x800431c4u, 0x80470f78u
            };
            static bool ev_done[96] = {};
            static uint32_t cnt_n[96] = {};
            const unsigned ev_count = (unsigned)(sizeof(ev_pcs)/sizeof(ev_pcs[0]));
            for (unsigned ei = 0; ei < ev_count; ++ei) {
                if (epc == ev_pcs[ei] && !ev_done[ei]) {
                    ev_done[ei] = true;
                    printf("#EV %u pc=%08x cyc=%llu\n", ei, (unsigned)epc,
                           (unsigned long long)cyc);
                    for (auto t : trace)
                        printf("#EVT %08x %08x %u %08x %08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
                }
            }
            const unsigned cnt_count = (unsigned)(sizeof(cnt_pcs)/sizeof(cnt_pcs[0]));
            for (unsigned ri = 0; ri < cnt_count; ++ri) {
            if (epc == cnt_pcs[ri]) {
                ++cnt_n[ri];
                if (cnt_n[ri] <= 5u || (cnt_n[ri] % 1000u) == 0u) {
                    printf("#PC %08x n=%u cyc=%llu rd=%u wv=%08x\n",
                           (unsigned)cnt_pcs[ri], (unsigned)cnt_n[ri],
                           (unsigned long long)cyc, (unsigned)model->ex_rd,
                           (unsigned)model->ex_wv);
                }
            }
            if (platform_stop && epc == 0x804753d0u) platform_seen = true;
        }
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
