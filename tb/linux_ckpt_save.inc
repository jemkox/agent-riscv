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
