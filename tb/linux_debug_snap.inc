        if (trace.size() == 200 && cyc && (cyc % 5000000u == 0u)) {
            printf("#SNAP cycles=%llu\n", (unsigned long long)cyc);
            for (auto t : trace) printf("#TRACE %08x %08x %u %08x %08x\n", t.pc, t.insn, t.rd, t.wv, t.ea);
        }
