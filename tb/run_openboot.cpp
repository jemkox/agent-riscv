// Open-boot runner: QEMU-virt-style handoff for OpenSBI fw_jump.bin + Sv32 kernel.
// Layout (fw_jump.bin bakes payload=+0x400000, fdt=+0x2200000):
//   stub @0x1000 -> a1=fw baked hint 0x1020 (x11 seed), OpenSBI scans RAM
//   fw_jump.bin   @0x80000000 | kernel Image @0x80400000
//   DTB          @0x83e00000 (env DTB_ADDR) | initrd cpio @0x83ecda00 (env INITRD_ADDR)
//   dts initrd range 0x83ecda00..0x83fffa80; stub DTB copy still at 0x1020 (spike a1 hint)
// Usage: run_openboot <fw.bin> <Image> <rootfs.cpio> <dtb> [max_cycles] [prompt]
//        [rec_start] [save|restore <ckpt> <hash>] [retire_bin] [boot_log]
// Output paths: argv 12/13 (or env RETIRE_BIN/BOOT_LOG); default $(B)/linux/*.
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
static uint32_t DTB_ADDR      = 0x83e00000u;
static uint32_t INITRD_ADDR = 0x83ecda00u;
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
    const bool shell_stop = (argc > 6) && !std::strcmp(argv[6], "shell");
    // Optional checkpoint mode (L7 speed-up): args 8/9/10 = save|restore <file> <hash>.
    // The hash guards stale checkpoints: the Makefile passes sha256 over RTL+inputs;
    // restore refuses to continue if it differs (any RTL/firmware/DTS change invalidates).
    const bool ckpt_save = (argc > 8) && !std::strcmp(argv[8], "save");
    const bool ckpt_restore = (argc > 8) && !std::strcmp(argv[8], "restore");
    const std::string ckpt_file = (argc > 9) ? std::string(argv[9]) : std::string();
    const std::string ckpt_hash = (argc > 10) ? std::string(argv[10]) : std::string();
    // Retire-trace + boot-log output paths (review: no hard-coded out-of-tree
    // paths in the runner): argv 12/13 win, then env RETIRE_BIN/BOOT_LOG,
    // then the default build-linux/linux/ (make passes $(B)-based paths).
    std::string retire_path, bootlog_path;
    if (argc > 11) retire_path = argv[11];
    if (argc > 12) bootlog_path = argv[12];
    if (retire_path.empty()) if (const char *e = getenv("RETIRE_BIN")) retire_path = e;
    if (bootlog_path.empty()) if (const char *e = getenv("BOOT_LOG")) bootlog_path = e;
    if (retire_path.empty()) retire_path = "build/linux/cpu_retire.bin";
    if (bootlog_path.empty()) bootlog_path = "build/linux/cpu_boot.log";
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
    const bool dump_trace = getenv("DUMP_TRACE") != nullptr;
    const uint32_t stuck_limit = dump_trace && getenv("STUCK_LIMIT") ? (uint32_t)strtoul(getenv("STUCK_LIMIT"), 0, 10)
        : (dump_trace ? 25000u : 0u);
    const uint32_t trace_minpc = getenv("TRACE_MINPC") ? (uint32_t)strtoul(getenv("TRACE_MINPC"), 0, 16) : 0u;
    const uint32_t trace_max = dump_trace && getenv("TRACE_MAX") ? (uint32_t)strtoul(getenv("TRACE_MAX"), 0, 10)
        : (dump_trace ? 20000000u : 0u);
    uint64_t insns = 0;
    std::deque<unsigned char> uart_input;
    bool done_seen = false, prompt_seen = false;
    bool login_prompt_seen = false, login_sent = false, password_sent = false, commands_sent = false, done_sent = false;
    bool uname_ok = false, cpuinfo_ok = false, ls_ok = false;
    uint64_t login_prompt_cyc = 0;
    uint32_t uart_dbg_count = 0;
    auto queue_text = [&](const std::string &s) {
        printf("#QUEUE len=%zu text=%s\n", s.size(), s.c_str());
        for (unsigned char c : s) uart_input.push_back(c);
    };
    // PAST_PANIC: keep running (do not break on 'Kernel panic') so a retire trace
    // can be captured THROUGH the /init panic (for self-consistency checkers).
    const bool past_panic = getenv("PAST_PANIC") != nullptr;
    FILE *rtf = fopen(retire_path.c_str(),
                      ckpt_restore ? "ab" : "wb");
    uint32_t rec_n = 0;
    uint64_t cyc = 0;
    std::string log;
    auto recent_tail = [&](const std::string &needle, size_t max_after) {
        size_t p = log.rfind(needle);
        return p != std::string::npos && (log.size() - (p + needle.size())) <= max_after;
    };
    auto saw_after = [&](const std::string &cmd, const std::string &out) {
        size_t p = log.rfind(cmd);
        return p != std::string::npos && log.find(out, p + cmd.size()) != std::string::npos;
    };
    auto done_output_seen = [&]() {
        size_t p = log.rfind("echo LINUX_SIM_DONE");
        if (p == std::string::npos) return false;
        p += 19;
        while (p < log.size() && (log[p] == '\n' || log[p] == '\r' || log[p] == ' ')) ++p;
        if (log.size() < p + 14) return false;
        if (log.compare(p, 14, "LINUX_SIM_DONE") != 0) return false;
        size_t q = p + 14;
        return q == log.size() || log[q] == '\n' || log[q] == '\r' || log[q] == ' ';
    };
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
        is >> cyc >> rec_n >> insns >> banner >> runinit >> login >> hangseen >> stuckdumped
           >> last_pc >> last_insn;
        uint32_t cnt; is >> cnt;
        for (uint32_t i = 0; i < cnt; i++) { uint32_t k, v; is >> k >> v; pcseen[k] = v; }
        is >> cnt;
        for (uint32_t i = 0; i < cnt; i++) { TEntry t; is >> t.pc >> t.insn >> t.rd >> t.wv >> t.ea; trace.push_back(t); }
        is >> cnt;
        for (uint32_t i = 0; i < cnt; i++) { TEntry t; is >> t.pc >> t.insn >> t.rd >> t.wv >> t.ea; trace_first.push_back(t); }
        is >> log;
        is >> contextp.get() >> *model;
        {
            bool have_shell_state = false;
            uint32_t marker = 0;
            is >> marker;
            have_shell_state = (marker == 1u);
            if (have_shell_state) {
                uint32_t u;
                is >> u; login_prompt_seen = (u != 0);
                is >> login_prompt_cyc;
                is >> u; login_sent = (u != 0);
                is >> u; password_sent = (u != 0);
                is >> u; commands_sent = (u != 0);
                is >> u; done_sent = (u != 0);
                is >> u; done_seen = (u != 0);
                is >> u; prompt_seen = (u != 0);
                is >> u; uname_ok = (u != 0);
                is >> u; cpuinfo_ok = (u != 0);
                is >> u; ls_ok = (u != 0);
                is >> u; panicked = (u != 0);
                is >> u; panicked_dumped = (u != 0);
                uint32_t qs = 0; is >> qs;
                for (uint32_t qi = 0; qi < qs; qi++) {
                    uint32_t c = 0; is >> c;
                    uart_input.push_back((unsigned char)c);
                }
            } else if (log.find("login:") != std::string::npos) {
                login = true;
                login_prompt_seen = true;
                login_prompt_cyc = cyc;
                printf("#CKPT_NO_SHELL_STATE log has login: but no trailing marker\n");
            }
            printf("#CKPT_SHELL_MARK=%d prompt_cyc=%llu qs=%u\n",
                   have_shell_state ? 1 : 0,
                   (unsigned long long)login_prompt_cyc,
                   (unsigned)uart_input.size());
        }
        // Review fix: rec_n is the SAVE-run record counter (capped at the save run's
        // TRACE_MAX). Restoring it would block the writer (rec_n < trace_max) for a
        // restore whose new run writes a FRESH file, so the trace restarts at 0.
        rec_n = 0;
        printf("#CKPT_RESTORE cyc=%llu insns=%u loglen=%zu\n",
               (unsigned long long)cyc, rec_n, log.size());
        printf("#CKPT_STATE banner=%d runinit=%d login=%d hang=%d stuck=%d "
               "panic=%d paniced=%d prompt=%d login_sent=%d password=%d "
               "commands=%d done_sent=%d done=%d halt=%d\n",
               banner ? 1 : 0, runinit ? 1 : 0, login ? 1 : 0,
               hangseen ? 1 : 0, stuckdumped ? 1 : 0,
               panicked ? 1 : 0, panicked_dumped ? 1 : 0,
               login_prompt_seen ? 1 : 0, login_sent ? 1 : 0,
               password_sent ? 1 : 0, commands_sent ? 1 : 0,
               done_sent ? 1 : 0, done_seen ? 1 : 0, model->halt ? 1 : 0);
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

    struct LogMatch {
        std::string n, p;
        bool f = false;
        LogMatch(const char *s) : n(s) {}
        void feed(char c) {
            if (f || n.empty()) return;
            if (p.size() + 1 > n.size()) p.erase(0, p.size() + 1 - n.size());
            p.push_back(c);
            if (p == n) f = true;
        }
    };
    LogMatch m_open("OpenSBI v"), m_init("Run /init as init process"),
             m_login("login:"), m_panic("Kernel panic");
    printf("openboot: fw %zu ins, kernel %zu ins, initrd %zu ins, dtb %zu ins (restore=%d)\n",
           fw.size(), kernel.size(), initrd.size(), dtb.size(), ckpt_restore ? 1 : 0);
    const uint64_t start_cyc = cyc;
    const bool save_at_end = ckpt_save || ckpt_restore;
    const uint64_t save_cycle = save_at_end ? start_cyc + max_cycles - 1 : 0ull;
    uint32_t loop_dbg = 0;
    while (cyc - start_cyc < max_cycles) {
            if (false && loop_dbg < 1000u) {
            printf("#LOOP_START cyc=%llu pc=%08x insn=%08x valid=%u halt=%u\n",
                   (unsigned long long)cyc, last_pc, last_insn,
                   (unsigned)model->rv_valid, (unsigned)model->halt);
            fflush(stdout);
            ++loop_dbg;
        }
        if (save_at_end && cyc == save_cycle) {
            printf("#CKPT_SAVE cyc=%llu insns=%u file=%s hash=%s\n",
                   (unsigned long long)cyc, rec_n, ckpt_file.c_str(), ckpt_hash.c_str());
            VerilatedSave os;
            os.open(ckpt_file.c_str());
            if (!os.isOpen()) { printf("#CKPT_FAIL cannot create %s\n", ckpt_file.c_str()); return 1; }
            os << ckpt_hash;
            os << (uint64_t)cyc; os << rec_n; os << insns;
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
            os << (uint32_t)1u;
            os << (uint32_t)(login_prompt_seen ? 1u : 0u);
            os << (uint64_t)login_prompt_cyc;
            os << (uint32_t)(login_sent ? 1u : 0u);
            os << (uint32_t)(password_sent ? 1u : 0u);
            os << (uint32_t)(commands_sent ? 1u : 0u);
            os << (uint32_t)(done_sent ? 1u : 0u);
            os << (uint32_t)(done_seen ? 1u : 0u);
            os << (uint32_t)(prompt_seen ? 1u : 0u);
            os << (uint32_t)(uname_ok ? 1u : 0u);
            os << (uint32_t)(cpuinfo_ok ? 1u : 0u);
            os << (uint32_t)(ls_ok ? 1u : 0u);
            os << (uint32_t)(panicked ? 1u : 0u);
            os << (uint32_t)(panicked_dumped ? 1u : 0u);
            os << (uint32_t)uart_input.size();
            for (unsigned char c : uart_input) os << (uint32_t)c;
            if (!os.isOpen()) { printf("#CKPT_FAIL save stream closed\n"); return 1; }
            os.close();
            {
                FILE *lf = fopen(bootlog_path.c_str(), "w");
                if (lf) {
                    fwrite(log.data(), 1, log.size(), lf);
                    fprintf(lf, "\n[cycles %llu banner %d runinit %d login %d halt %d]\n",
                            (unsigned long long)cyc, banner ? 1 : 0,
                            runinit ? 1 : 0, login ? 1 : 0, model->halt ? 1 : 0);
                    fclose(lf);
                }
            }
            model->final();
            return 0;
        }
        if (login_prompt_seen && login_prompt_cyc != 0 && !login_sent &&
            cyc >= login_prompt_cyc + 5000000ull && uart_input.empty()) {
            queue_text("root\n");
            login_sent = true;
            password_sent = false;
        }
        if (login_sent && !password_sent && uart_input.empty() &&
            (recent_tail("Password:", 8) ||
             (login_prompt_cyc != 0 && cyc >= login_prompt_cyc + 14000000ull))) {
            queue_text("\n");
            password_sent = true;
        }
        // uart: one up/down clock pair per iteration
        for (int half = 0; half < 2; half++) {
            model->clk = (uint32_t)half;
            model->reset = 0;
            model->lwe = 0; model->lwa = 0; model->lwd = 0;
            bool feed_ready = (!model->uart_rx_pending && !uart_input.empty());
            uint32_t feed_rx = feed_ready ? (uint32_t)uart_input.front() : 0u;
            bool pre_pending = !model->uart_rx_pending;
            model->uart_rx_ready = feed_ready ? 1u : 0u;
            model->uart_rx_in = (uint8_t)feed_rx;
            if (false && loop_dbg < 1000u) {
                printf("#HALF eval=%d cyc=%llu pc=%08x ea=%08x ready=%u pending=%u\n",
                       half, (unsigned long long)cyc, (unsigned)model->ex_pc,
                       (unsigned)model->ex_ea, (unsigned)model->uart_rx_ready,
                       (unsigned)model->uart_rx_pending);
                fflush(stdout);
            }
            model->eval();
            if (false && loop_dbg < 30u) {
                printf("#HALF done=%d cyc=%llu ex_pc=%08x ex_ea=%08x valid=%u halt=%u\n",
                       half, (unsigned long long)cyc, (unsigned)model->ex_pc,
                       (unsigned)model->ex_ea, (unsigned)model->rv_valid,
                       (unsigned)model->halt);
                fflush(stdout);
                ++loop_dbg;
            }
            bool uart_load = ((model->ex_insn & 0x7fu) == 0x03u) &&
                             (model->ex_ea == 0x10000000u);
            if ((!uart_input.empty() || model->uart_rx_pending || uart_load ||
                 (login_prompt_seen && login_prompt_cyc != 0 &&
                  cyc >= login_prompt_cyc + 4990000ull &&
                  cyc < login_prompt_cyc + 5010000ull)) &&
                uart_dbg_count < 20000u) {
                ++uart_dbg_count;
                printf("#UARTDBG cyc=%llu half=%d queue=%zu pending=%u ready=%u ex_pc=%08x ex_insn=%08x ex_ea=%08x uart_load=%d\n",
                       (unsigned long long)cyc, half, uart_input.size(),
                       (unsigned)model->uart_rx_pending, (unsigned)model->uart_rx_ready,
                       (unsigned)model->ex_pc, (unsigned)model->ex_insn,
                       (unsigned)model->ex_ea, uart_load ? 1 : 0);
            }
            if (feed_ready && (model->uart_rx_pending || (pre_pending && uart_load))) {
                printf("#STDIN cyc=%llu half=%d ch=%02x ascii=%c\n",
                       (unsigned long long)cyc, half, feed_rx,
                       (feed_rx >= 32u && feed_rx < 127u) ? (char)feed_rx : '.');
                uart_input.pop_front();
            }
            if (model->rv_valid) {
                insns++;
                last_pc = model->ex_pc; last_insn = model->ex_insn;
                if (dump_trace) {
                    TEntry t{model->ex_pc, model->ex_insn, model->ex_rd,
                             model->ex_wv, model->ex_ea};
                    trace.push_back(t);
                    if (trace.size() > 400) trace.pop_front();
                    if (trace_first.size() < 1200 && half == 1) trace_first.push_back(t);
                    if (rtf && rec_n < trace_max && half == 1 && cyc >= rec_start &&
                        t.pc >= trace_minpc) {
                        uint32_t top_op = t.insn & 0x7fu;
                        uint32_t is_st = (top_op == 0x23u) ? 1u : 0u;
                        uint32_t sd_val = (uint32_t)model->ex_sd;
                        uint32_t rec[8] = {(uint32_t)cyc, t.pc, t.insn, t.rd, t.wv,
                                           is_st, t.ea, sd_val};
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
            }
            if (model->uart_tx_valid && half == 1) {
                char ch = (char)(model->uart_tx_out & 0xFFu);
                log.push_back(ch);
                m_open.feed(ch);
                m_init.feed(ch);
                m_login.feed(ch);
                m_panic.feed(ch);
                if (done_output_seen()) done_seen = true;
                if (login_sent && !password_sent && uart_input.empty() &&
                    (recent_tail("Password:", 8) ||
                     (login_prompt_cyc != 0 &&
                      cyc >= login_prompt_cyc + 14000000ull))) {
                    queue_text("\n");
                    password_sent = true;
                }
                if (login_sent && !password_sent && uart_input.empty() &&
                    recent_tail("login on", 16)) {
                    password_sent = true;
                    printf("#LOGIN_SUCCESS cyc=%llu\n", (unsigned long long)cyc);
                }
                if (login_sent && password_sent && !commands_sent && uart_input.empty() &&
                    (recent_tail("# ", 2) || recent_tail("$ ", 2))) {
                    queue_text("uname -a\ncat /proc/cpuinfo\nls /\n");
                    commands_sent = true;
                }
                if (!uname_ok && saw_after("uname", "Linux ")) uname_ok = true;
                if (!cpuinfo_ok && saw_after("cat /proc/cpuinfo", "processor")) cpuinfo_ok = true;
                if (!ls_ok && saw_after("ls /", "bin")) ls_ok = true;
                if (!done_sent && uname_ok && cpuinfo_ok && ls_ok && uart_input.empty()) {
                    queue_text("echo LINUX_SIM_DONE\n");
                    done_sent = true;
                }
            }
        }
        if (cyc && (cyc % 100000000ull) == 0) {
            size_t tailpos = log.size() > 160 ? log.size() - 160 : 0;
            printf("#PROG cyc=%llu loglen=%zu pc=%08x insn=%08x tail=%s\n",
                   (unsigned long long)cyc, log.size(), last_pc, last_insn,
                   log.c_str() + tailpos);
            fflush(stdout);
        }
        banner = banner || m_open.f;
        runinit = runinit || m_init.f;
        if (!login && m_login.f) {
            login = true;
            login_prompt_seen = true;
            login_prompt_cyc = cyc;
        }
        panicked = panicked || m_panic.f;
        if (panicked && !panicked_dumped) {
            panicked_dumped = true;
            printf("#PANIC_CONTEXT (ring at first 'Kernel panic'):\n");
            for (const auto &e : trace)
                printf("#PANI %08x %08x r%u<-%08x ea=%08x\n", e.pc, e.insn, e.rd, e.wv, e.ea);
        }
        bool stop_login = login && prompt_stop;
        bool stop_done = shell_stop && done_seen;
        bool stop_panic = panicked && !past_panic;
        bool stop_halt = model->halt;
        if (stop_login || stop_done || stop_panic || stop_halt) {
            printf("#STOP cyc=%llu login=%d prompt_stop=%d done=%d shell_stop=%d "
                   "panic=%d past_panic=%d halt=%d\n",
                   (unsigned long long)cyc, login ? 1 : 0, prompt_stop ? 1 : 0,
                   done_seen ? 1 : 0, shell_stop ? 1 : 0,
                   panicked ? 1 : 0, past_panic ? 1 : 0, stop_halt ? 1 : 0);
            break;
        }
        cyc++;
    }

    printf("#OPENBOOT cyc=%llu banner=%d runinit=%d login=%d halt=%d panic=%d loglen=%zu\n",
           (unsigned long long)cyc, banner ? 1 : 0, runinit ? 1 : 0,
           login ? 1 : 0, model->halt ? 1 : 0, panicked ? 1 : 0, log.size());
    {
        FILE *f = fopen(bootlog_path.c_str(), "w");
        if (f) { fwrite(log.data(), 1, log.size(), f);
                 fprintf(f, "\n[cycles %llu banner %d runinit %d login %d halt %d]\n",
                         (unsigned long long)cyc, banner ? 1 : 0,
                         runinit ? 1 : 0, login ? 1 : 0, model->halt ? 1 : 0);
                 fclose(f); }
    }
    printf("#LINUX cycles=%llu insns=%llu prompt=%d login=%d done=%d halt=%d cmds=%d dtb=%08x\n",
           (unsigned long long)cyc, (unsigned long long)insns,
           login_prompt_seen ? 1 : 0, login ? 1 : 0, done_seen ? 1 : 0,
           model->halt ? 1 : 0,
           (uname_ok && cpuinfo_ok && ls_ok) ? 1 : 0, DTB_ADDR);
    if (!login) {
        for (const auto &t : trace_first)
            printf("#TRACE_FIRST %08x %08x r%u<-%08x ea=%08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
        for (const auto &t : trace)
            printf("#TRACE %08x %08x r%u<-%08x ea=%08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
    }
    if (login && prompt_stop)
        printf("OPENBOOT OK: OpenSBI banner + init + login prompt on our CPU\n");
    if (done_seen && shell_stop)
        printf("OPENBOOT OK: OpenSBI + MMU Linux shell commands + LINUX_SIM_DONE on our CPU\n");
    model->final();
    return (login && prompt_stop) ? 0 : (banner && login ? 0 : 1);
}
