static bool load_bin(const char *path, std::vector<uint32_t> &out) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return false; }
    out.resize((size_t)((sz + 3) / 4));
    for (size_t i = 0; i < out.size(); i++) {
        uint32_t w = 0;
        unsigned char b[4] = {0,0,0,0};
        size_t n = fread(b, 1, 4, f);
        if (n != 4 && feof(f)) {
            for (size_t k=0;k<n;k++) w |= ((uint32_t)b[k]) << (8*k);
            out[i] = w;
        } else if (n == 4) {
            out[i] = (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
                     ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
        } else {
            fclose(f); return false;
        }
    }
    fclose(f);
    return true;
}
