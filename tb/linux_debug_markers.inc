            {
                uint32_t p = model->ex_pc;
                static int handler_seen = 0;
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
                if (p == 0x80473db4u || p == 0x80473dbcu) {
                    printf("#HND_CSW cyc=%llu pc=%08x rd=%u wv=%08x ea=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv,
                           (unsigned)model->ex_ea);
                }
                if (p == 0x80473db8u) {
                    printf("#HND_BR cyc=%llu pc=%08x\n", (unsigned long long)cyc, (unsigned)p);
                }
                if (p == 0x80473e7cu) {
                    printf("#HND_CLR cyc=%llu pc=%08x rd=%u wv=%08x ea=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv,
                           (unsigned)model->ex_ea);
                }
                if ((p == 0x80473e54u || p == 0x80473e58u || p == 0x80473e5cu) &&
                    (cyc < 100000000u || handler_seen < 40)) {
                    printf("#HND_CSR cyc=%llu pc=%08x rd=%u wv=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv);
                    if (p == 0x80473e5cu) handler_seen++;
                }
                static int tcalled = 0, caslr = 0, cassc = 0, sigld = 0, wfi_cnt = 0, sigset = 0;
                static int path_seen = 0;
                bool show_path = (path_seen < 40 || cyc > 100000000u);
                if (p == 0x80473e90u) {
                    printf("#CALL_TIMER cyc=%llu pc=%08x rd=%u wv=%08x\n",
                           (unsigned long long)cyc, (unsigned)p,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv);
                }
                if (p == 0x8046c920u && show_path) {
                    printf("#TCALL cyc=%llu pc=%08x\n", (unsigned long long)cyc, (unsigned)p);
                    if (cyc <= 100000000u) tcalled++;
                }
                static const uint32_t path_pcs[] = {
                    0x8046ca60u, 0x8046c940u, 0x8046c94cu, 0x8046c950u,
                    0x8046c954u, 0x8046c960u, 0x80473fa0u, 0x80473fb8u,
                    0x80473fc0u, 0x80473fc4u, 0x8046bbdcu, 0x8046bbe8u,
                    0x8046bbf8u, 0x8046bbfcu, 0x8046bc00u,
                    0x8000da54u,
                    0x8000da60u, 0x8000da64u, 0x8000da68u, 0x8000da70u, 0x8000da74u,
                    0x8000da78u, 0x8000da7cu, 0x8000da80u, 0x8000da84u, 0x8000da8cu
                };
                if (show_path) {
                    for (uint32_t q : path_pcs) {
                        if (p != q) continue;
                        printf("#PATH cyc=%llu pc=%08x rd=%u wv=%08x ea=%08x st=%u sd=%08x\n",
                               (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_rd,
                               (unsigned)model->ex_wv, (unsigned)model->ex_ea,
                               (unsigned)model->ex_st, (unsigned)model->ex_sd);
                        if (p == 0x8000da84u) path_seen++;
                        break;
                    }
                }
                if (p == 0x8047bffc && (caslr < 8 || cyc > 100000000u)) {
                    printf("#CAS_LR cyc=%llu pc=%08x ea=%08x rd=%u wv=%08x\n",
                           (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_ea,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv);
                    caslr++;
                }
                if (p == 0x8047c004 && (cassc < 8 || cyc > 100000000u)) {
                    printf("#CAS_SC cyc=%llu pc=%08x st=%u rd=%u wv=%08x sd=%08x\n",
                           (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_st,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv, (unsigned)model->ex_sd);
                    cassc++;
                }
                if (p == 0x80473ef4u) {
                    printf("#VSN_SC cyc=%llu pc=%08x ea=%08x st=%u rd=%u wv=%08x sd=%08x\n",
                           (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_ea,
                           (unsigned)model->ex_st, (unsigned)model->ex_rd,
                           (unsigned)model->ex_wv, (unsigned)model->ex_sd);
                }
                if (p == 0x8003c990u && (sigld < 8 || cyc > 100000000u)) {
                    printf("#SIG_LD cyc=%llu pc=%08x ea=%08x rd=%u wv=%08x\n",
                           (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_ea,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv);
                    sigld++;
                }
                if ((p == 0x80034cb0u || p == 0x8001532cu || p == 0x8046db84u) && (sigset < 12 || cyc > 100000000u)) {
                    printf("#SIG_SET cyc=%llu pc=%08x st=%u rd=%u wv=%08x ea=%08x sd=%08x\n",
                           (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_st,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv, (unsigned)model->ex_ea,
                           (unsigned)model->ex_sd);
                    sigset++;
                }
                if (p == 0x8046bbbcu && (wfi_cnt < 8 || cyc > 100000000u)) {
                    printf("#WFI cyc=%llu pc=%08x\n", (unsigned long long)cyc, (unsigned)p);
                    wfi_cnt++;
                }
                if (model->ex_ea == 0x805cb4a8u) {
                    printf("#MEM40 cyc=%llu pc=%08x st=%u rd=%u wv=%08x ea=%08x sd=%08x\n",
                           (unsigned long long)cyc, (unsigned)p, (unsigned)model->ex_st,
                           (unsigned)model->ex_rd, (unsigned)model->ex_wv,
                           (unsigned)model->ex_ea, (unsigned)model->ex_sd);
                }
            }
