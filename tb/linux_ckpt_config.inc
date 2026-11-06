    const bool ckpt_save = (argc > 5) && !std::strcmp(argv[5], "save");
    const bool ckpt_restore = (argc > 5) && !std::strcmp(argv[5], "restore");
    const bool ckpt_mark = (argc > 5) && !std::strcmp(argv[5], "mark");
    const uint64_t mark_cycle = (ckpt_mark && argc > 6) ? strtoull(argv[6], nullptr, 10) : 0ull;
    const uint64_t save_cycle = (ckpt_save && max_cycles > 0) ? (max_cycles - 1) : 0ull;
    const std::string ckpt_file = (argc > 6 && (ckpt_save || ckpt_restore)) ? std::string(argv[6]) : std::string();
    const std::string ckpt_hash_arg = (argc > 7 && (ckpt_save || ckpt_restore)) ? std::string(argv[7]) : std::string();
