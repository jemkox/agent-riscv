    struct Gate { std::string name; uint32_t pc; bool seen; };
    std::vector<Gate> gates;
    {
        FILE *gf = fopen("linux/gate.txt", "r");
        if (gf) {
            char nm[64];
            unsigned long long pcv;
            while (fscanf(gf, "%63s %llx", nm, &pcv) == 2)
                gates.push_back({nm, (uint32_t)pcv, false});
            fclose(gf);
        }
    }
    auto gate_seen = [&](const char *name) {
        for (const auto &g : gates)
            if (g.name == name) return g.seen;
        return false;
    };
