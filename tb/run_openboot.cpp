// Open-boot runner: QEMU-virt-style handoff for OpenSBI fw_jump.bin + Sv32 kernel.
// Layout (fw_jump.bin bakes payload=+0x400000, fdt=+0x2200000):
//   stub @0x1000 -> a1=fw baked hint 0x1020 (x11 seed), OpenSBI scans RAM
//   fw_jump.bin   @0x80000000 | kernel Image @0x80400000
//   FDT          @0x82200000 | initrd cpio @0x82400000
// Usage: run_openboot <fw.bin> <Image> <rootfs.cpio> <linux.dtb> [max_cycles] [prompt]
#include <verilated.h>
#include <memory>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <deque>
#include <unordered_map>
#include <verilated_save.h>
#include "Vrun_linux.h"

static const uint32_t FW_ADDR     = 0x80000000u;
static const uint32_t KERNEL_ADDR = 0x80400000u;
static uint32_t DTB_ADDR      = 0x82200000u;
static uint32_t INITRD_ADDR = 0x82800000u;
static void apply_addr_env() {
    if (const char *e = getenv("DTB_ADDR"))    DTB_ADDR = (uint32_t)strtoul(e, nullptr, 16);
    if (const char *e = getenv("INITRD_ADDR")) INITRD_ADDR = (uint32_t)strtoul(e, nullptr, 16);
}
static const uint32_t STUB_ADDR   = 0x00001000u;
// Pinned-spike boot: fw_jump's stub sets a1 = 0x1020 (the fw's baked DTB hint),
// then OpenSBI's find_device_tree scan locates the real DTB in RAM.  The RTL
// boot starts directly at FW_ADDR, so seed x11 with the same baked hint (NOT
// DTB_ADDR): seeding the real addr made "found == hint" and took a different
// OpenSBI path than spike (divergence at the scan result, boot panic).
static const uint32_t STUB_HINT   = 0x00001020u;

static bool load_bin(const char *path, std::vector<uint32_t> &words) {
    FILE *f = fopen(path, "rb");
    if (!f) { printf("cannot read %s\n", path); return false; }
    fseek(f, 0, SEEK_END);
    long n = (ftell(f) + 3) / 4;
    fseek(f, 0, SEEK_SET);
    words.resize((size_t)n, 0u);
    for (long i = 0; i < n; i++) {
        unsigned char b[4] = {0, 0, 0, 0};
        size_t r = fread(b, 1, 4, f);
        uint32_t w = 0;
        for (size_t k = 0; k < r; k++) w |= (uint32_t)b[k] << (8 * k);
        words[(size_t)i] = w;
    }
    fclose(f);
    return true;
}

int main(int argc, char **argv) {
    if (argc < 5) {
        printf("usage: run_openboot <fw.bin> <Image> <rootfs.cpio> <dtb> [max_cycles] [prompt]\n");
        return 2;
    }
    apply_addr_env();
    Verilated::commandArgs(argc, argv);
    std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    std::unique_ptr<Vrun_linux> model{new Vrun_linux(contextp.get())};

    std::vector<uint32_t> fw, kernel, initrd, dtb;
    if (!load_bin(argv[1], fw) || !load_bin(argv[2], kernel) ||
        !load_bin(argv[3], initrd) || !load_bin(argv[4], dtb))
        return 1;
    const uint64_t max_cycles = (argc > 5) ? strtoull(argv[5], nullptr, 10)
                                           : 4000000000ull;
    const bool prompt_stop = (argc > 6) && !std::strcmp(argv[6], "prompt");
    // Optional checkpoint mode (L7 speed-up): args 8/9/10 = save|restore <file> <hash>.
    // The hash guards stale checkpoints: the Makefile passes sha256 over RTL+inputs;
    // restore refuses to continue if it differs (any RTL/firmware/DTS change invalidates).
    const bool ckpt_save = (argc > 8) && !std::strcmp(argv[8], "save");
    const bool ckpt_restore = (argc > 8) && !std::strcmp(argv[8], "restore");
    const std::string ckpt_file = (argc > 9) ? std::string(argv[9]) : std::string();
    const std::string ckpt_hash = (argc > 10) ? std::string(argv[10]) : std::string();
    // Kernel entry: the Image file is loaded whole at KERNEL_ADDR (as QEMU virt
    // does); its first u32 is a J-type jump to the head entry. FW_JUMP_ADDR (baked
    // into the fw_jump build) must equal this; we print it for cross-checking.
    size_t kentry = 0;
    uint32_t w0 = kernel.empty() ? 0 : kernel[0];
    if ((w0 & 0x7f) == 0x6f) {
        int32_t imm = (int32_t)((((w0 >> 31) & 1u) << 20) |
                               (((w0 >> 12) & 0xffu) << 12) |
                               (((w0 >> 20) & 1u) << 11) |
                               (((w0 >> 21) & 0x3ffu) << 1));
        kentry = (size_t)(uint32_t)(imm / 4);   // words from KERNEL_ADDR
    }
    if (kentry == 0) {  // fallback: first {csrw sie, csrw sip} pair
        for (size_t i = 0; kentry == 0 && i + 1 < kernel.size(); i++)
            if (kernel[i] == 0x10401073u && kernel[i + 1] == 0x14401073u) kentry = i;
    }
    if (kentry == 0) { printf("no kernel head entry found in Image\n"); return 3; }
    printf("kernel entry = %08x (base +%04x)\n", KERNEL_ADDR + (uint32_t)kentry * 4u,
           (unsigned)(kentry * 4u));
    const uint64_t rec_start = (argc > 7) ? strtoull(argv[7], nullptr, 10)
        : (getenv("REC_START") ? strtoull(getenv("REC_START"), nullptr, 10) : 0ull);
    struct TEntry { uint32_t pc, insn, rd, wv, ea; };
    bool banner = false, runinit = false, login = false, hangseen = false;
    bool stuckdumped = false, panicked = false, panicked_dumped = false;
    std::deque<TEntry> trace, trace_first;
    std::unordered_map<uint32_t, uint32_t> pcseen;
    const uint32_t stuck_limit = getenv("STUCK_LIMIT") ? (uint32_t)strtoul(getenv("STUCK_LIMIT"), 0, 10) : 25000u;
    const uint32_t trace_minpc = getenv("TRACE_MINPC") ? (uint32_t)strtoul(getenv("TRACE_MINPC"), 0, 16) : 0u;
    const uint32_t trace_max = getenv("TRACE_MAX") ? (uint32_t)strtoul(getenv("TRACE_MAX"), 0, 10) : 20000000u;
    FILE *rtf = fopen("../../build-linux/mmu3/cpu_retire.bin",
                      ckpt_restore ? "ab" : "wb");
    uint32_t rec_n = 0;
    uint64_t cyc = 0;
    std::string log;
    uint32_t last_pc = 0, last_insn = 0;
    if (ckpt_restore) {
        VerilatedRestore is;
        is.open(ckpt_file.c_str());
        if (!is.isOpen()) { printf("cannot open %s\n", ckpt_file.c_str()); return 4; }
        std::string h; is >> h;
        if (h != ckpt_hash) {
            printf("#CKPT_STALE stored=%s given=%s: RTL/firmware/DTS changed since save\n",
                   h.c_str(), ckpt_hash.c_str());
            return 5;
        }
        is >> cyc >> rec_n >> banner >> runinit >> login >> hangseen >> stuckdumped
           >> last_pc >> last_insn;
        uint32_t cnt; is >> cnt;
        for (uint32_t i = 0; i < cnt; i++) { uint32_t k, v; is >> k >> v; pcseen[k] = v; }
        is >> cnt;
        for (uint32_t i = 0; i < cnt; i++) { TEntry t; is >> t.pc >> t.insn >> t.rd >> t.wv >> t.ea; trace.push_back(t); }
        is >> cnt;
        for (uint32_t i = 0; i < cnt; i++) { TEntry t; is >> t.pc >> t.insn >> t.rd >> t.wv >> t.ea; trace_first.push_back(t); }
        is >> log;
        is >> contextp.get() >> *model;
        printf("#CKPT_RESTORE cyc=%llu insns=%u loglen=%zu\n",
               (unsigned long long)cyc, rec_n, log.size());
    } else {
        auto setc = [&](uint32_t clk, uint32_t reset, uint32_t lwe, uint32_t lwa,
                        uint32_t lwd) {
            model->clk = clk; model->reset = reset;
            model->lwe = lwe; model->lwa = lwa; model->lwd = lwd;
            model->linux_dtb_addr = STUB_HINT;
            model->uart_rx_ready = 0; model->uart_rx_in = 0;
            model->eval();
        };
        auto load_words = [&](uint32_t base, const std::vector<uint32_t> &w) {
            for (size_t i = 0; i < w.size(); i++) {
                if (!w[i]) continue;
                uint32_t addr = base + (uint32_t)i * 4u;
                setc(1, 1, 1, addr, w[i]);
                setc(0, 1, 1, addr, w[i]);
            }
        };
        setc(0, 1, 0, 0, 0);
        load_words(FW_ADDR, fw);
        load_words(KERNEL_ADDR, kernel);
        // pinned spike places the --dtb at RAM 0x1020 (its a1 hint address); load
        // the identical copy there so OpenSBI's scan-from-a1 sees byte-identical
        // memory (the kernel later reuses this low RAM, same as spike).
        load_words(0x1020, dtb);
        load_words(DTB_ADDR, dtb);
        load_words(INITRD_ADDR, initrd);
        setc(0, 0, 0, 0, 0);
    }

    auto scan = [&](const char *needle) {
        return log.find(needle) != std::string::npos;
    };
    printf("openboot: fw %zu ins, kernel %zu ins, initrd %zu ins, dtb %zu ins (restore=%d)\n",
           fw.size(), kernel.size(), initrd.size(), dtb.size(), ckpt_restore ? 1 : 0);
    const uint64_t start_cyc = cyc;
    const bool save_at_end = ckpt_save || ckpt_restore;
    const uint64_t save_cycle = save_at_end ? start_cyc + max_cycles - 1 : 0ull;
    while (cyc - start_cyc < max_cycles) {
        if (save_at_end && cyc == save_cycle) {
            printf("#CKPT_SAVE cyc=%llu insns=%u file=%s hash=%s\n",
                   (unsigned long long)cyc, rec_n, ckpt_file.c_str(), ckpt_hash.c_str());
            VerilatedSave os;
            os.open(ckpt_file.c_str());
            if (!os.isOpen()) { printf("#CKPT_FAIL cannot create %s\n", ckpt_file.c_str()); return 1; }
            os << ckpt_hash;
            os << (uint64_t)cyc; os << rec_n;
            os << banner << runinit << login << hangseen << stuckdumped;
            os << last_pc << last_insn;
            os << (uint32_t)pcseen.size();
            for (const auto &kv : pcseen) { os << kv.first; os << kv.second; }
            os << (uint32_t)trace.size();
            for (const auto &t : trace) { os << t.pc << t.insn << t.rd << t.wv << t.ea; }
            os << (uint32_t)trace_first.size();
            for (const auto &t : trace_first) { os << t.pc << t.insn << t.rd << t.wv << t.ea; }
            os << log;
            os << contextp.get();
            os << *model;
            if (!os.isOpen()) { printf("#CKPT_FAIL save stream closed\n"); return 1; }
            os.close();
            model->final();
            return 0;
        }
        // uart: one up/down clock pair per iteration
        for (int half = 0; half < 2; half++) {
            model->clk = (uint32_t)half;
            model->reset = 0;
            model->lwe = 0; model->lwa = 0; model->lwd = 0;
            model->uart_rx_ready = 0; model->uart_rx_in = 0;
            model->eval();
            if (model->rv_valid) {
                TEntry t{model->ex_pc, model->ex_insn, model->ex_rd,
                         model->ex_wv, model->ex_ea};
                last_pc = t.pc; last_insn = t.insn;
                trace.push_back(t);
                if (trace.size() > 400) trace.pop_front();
                if (trace_first.size() < 1200 && half == 1) trace_first.push_back(t);
                if (rtf && rec_n < trace_max && half == 1 && cyc >= rec_start &&
                    t.pc >= trace_minpc) {
                    uint32_t rec[8] = {(uint32_t)cyc, t.pc, t.insn, t.rd, t.wv,
                                       (uint32_t)(model->ex_st ? 1 : 0), t.ea,
                                       (uint32_t)model->ex_sd};
                    fwrite(rec, sizeof(rec), 1, rtf);
                    ++rec_n;
                }
                if (!hangseen && t.pc == 0x800003f8u) {
                    hangseen = true;
                    printf("#HANG_CONTEXT (ring at first wfi-halt):\n");
                    for (const auto &e : trace)
                        printf("#HANG %08x %08x r%u<-%08x ea=%08x\n", e.pc, e.insn, e.rd, e.wv, e.ea);
                }
                if (!stuckdumped && ++pcseen[t.pc] == stuck_limit) {
                    stuckdumped = true;
                    printf("#STUCK_CONTEXT (ring when pc %08x retired %ux):\n", t.pc, stuck_limit);
                    for (const auto &e : trace)
                        printf("#STUCK %08x %08x r%u<-%08x ea=%08x\n", e.pc, e.insn, e.rd, e.wv, e.ea);
                }
            }
            if (model->uart_tx_valid && half == 1) {
                char ch = (char)(model->uart_tx_out & 0xFFu);
                log.push_back(ch);
            }
        }
        if (cyc && (cyc % 20000000ull) == 0) {
            size_t tailpos = log.size() > 160 ? log.size() - 160 : 0;
            printf("#PROG cyc=%llu loglen=%zu pc=%08x insn=%08x tail=%s\n",
                   (unsigned long long)cyc, log.size(), last_pc, last_insn,
                   log.c_str() + tailpos);
            fflush(stdout);
        }
        banner = banner || scan("OpenSBI v");
        runinit = runinit || scan("Run /init as init process");
        login = login || scan("login:");
        panicked = panicked || scan("Kernel panic");
        if (panicked && !panicked_dumped) {
            panicked_dumped = true;
            printf("#PANIC_CONTEXT (ring at first 'Kernel panic'):\n");
            for (const auto &e : trace)
                printf("#PANI %08x %08x r%u<-%08x ea=%08x\n", e.pc, e.insn, e.rd, e.wv, e.ea);
        }
        if ((login && prompt_stop) || panicked || model->halt) break;
        cyc++;
    }

    printf("#OPENBOOT cyc=%llu banner=%d runinit=%d login=%d halt=%d panic=%d loglen=%zu\n",
           (unsigned long long)cyc, banner ? 1 : 0, runinit ? 1 : 0,
           login ? 1 : 0, model->halt ? 1 : 0, panicked ? 1 : 0, log.size());
    {
        FILE *f = fopen("../../build-linux/mmu3/cpu_boot.log", "w");
        if (f) { fwrite(log.data(), 1, log.size(), f);
                 fprintf(f, "\n[cycles %llu banner %d runinit %d login %d halt %d]\n",
                         (unsigned long long)cyc, banner ? 1 : 0,
                         runinit ? 1 : 0, login ? 1 : 0, model->halt ? 1 : 0);
                 fclose(f); }
    }
    if (!login) {
        for (const auto &t : trace_first)
            printf("#TRACE_FIRST %08x %08x r%u<-%08x ea=%08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
        for (const auto &t : trace)
            printf("#TRACE %08x %08x r%u<-%08x ea=%08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
    }
    if (login && prompt_stop)
        printf("OPENBOOT OK: OpenSBI banner + init + login prompt on our CPU\n");
    model->final();
    return (login && prompt_stop) ? 0 : (banner && login ? 0 : 1);
}
