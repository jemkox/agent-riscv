#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
static void mark(unsigned c) {
    *(volatile unsigned char *)(uintptr_t)0x1FF00000u = (unsigned char)c;
}
int main(void) {
    mark('A');
    FILE *f = fopen("doom1.wad", "rb");
    if (!f) { mark('f'); return 1; }
    mark('B');
    char b4[4];
    size_t m = fread(b4, 1, 4, f);
    mark('0' + (m & 15u));
    if (fseek(f, 16, SEEK_SET) != 0) { mark('s'); return 2; }
    mark('C');
    char buf[8];
    size_t n = fread(buf, 1, 8, f);
    mark('0' + (n & 15u));
    if (n != 8) { mark('R'); return 3; }
    char buf2[8];
    if (fseek(f, 24, SEEK_SET) != 0) { mark('t'); return 6; }
    size_t n2 = fread(buf2, 1, 8, f);
    mark('0' + (n2 & 15u));
    fclose(f);
    mark('D');
    FILE *g = fopen("cfg", "wb");
    if (!g) { mark('g'); return 5; }
    mark('E');
    fprintf(g, "%s %d\n", "x", 1);
    fclose(g);
    mark('F');
    printf("n=%zu s=%s\n", n, buf);
    void *h = malloc(1024);
    if (!h) { mark('m'); return 4; }
    memset(h, 1, 16);
    printf("%u\n", (unsigned)(size_t)h);
    mark('Z');
    return 0;
}
