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
