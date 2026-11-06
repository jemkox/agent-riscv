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
            login_prompt_seen = true;
        }
        auto recent_tail = [&](const std::string &s, size_t max_after) {
            size_t p = tail.rfind(s);
            if (p == std::string::npos) return false;
            return tail.size() - (p + s.size()) <= max_after;
        };
        if (recent_tail("login:", 8)) {
            login_prompt_cyc = cyc;
            if (login_sent && password_sent) {
                login_sent = false;
                password_sent = false;
            }
        }
        if (login_sent && !password_sent && uart_input.empty() &&
            recent_tail("Password:", 8)) {
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
        if (tail.find("uname") != std::string::npos) cmd_uname_seen = true;
        if (tail.find("cpuinfo") != std::string::npos) cmd_cpuinfo_seen = true;
        if (!uname_ok && saw_after("uname", "Linux ")) uname_ok = true;
        if (!cpuinfo_ok && saw_after("cat /proc/cpuinfo", "processor")) cpuinfo_ok = true;
        if (!ls_ok && saw_after("ls /", "bin")) ls_ok = true;
        if (!done_sent && uname_ok && cpuinfo_ok && ls_ok && uart_input.empty()) {
            queue_text("echo LINUX_SIM_DONE\n");
            done_sent = true;
        }
    };
