    auto feed_output = [&](uint32_t ch) {
#ifdef LINUX_DEBUG
        static uint32_t uart_tx_seen = 0;
        if (uart_tx_seen < 200000u) {
            ++uart_tx_seen;
            if (dbg_log)
                std::fprintf(dbg_log, "#UART_TX cyc=%llu ch=%02x ascii=%c\n",
                             (unsigned long long)cyc, (unsigned)(ch & 0xFFu),
                             (ch >= 32u && ch < 127u) ? (char)ch : '.');
        }
#endif
        std::putchar((char)ch);
        std::fflush(stdout);
        tail.push_back((char)ch);
        if (tail.size() > 8192) tail.erase(0, tail.size() - 8192);
        if (tail.find("LINUX_SIM_DONE") != std::string::npos) done_seen = true;
        if (tail.find("~ #") != std::string::npos || tail.find("~ $") != std::string::npos ||
            tail.find("/ #") != std::string::npos || tail.find("/ $") != std::string::npos ||
            tail.find("BusyBox") != std::string::npos)
            prompt_seen = true;
        if (tail.find("login:") != std::string::npos) {
            prompt_seen = true;
            login_ready = true;
        }
        if (tail.find("uname") != std::string::npos) cmd_uname_seen = true;
        if (tail.find("cpuinfo") != std::string::npos) cmd_cpuinfo_seen = true;
    };
