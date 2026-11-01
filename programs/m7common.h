#ifndef M7COMMON_H
#define M7COMMON_H 1
#include <stdint.h>
static volatile unsigned char *const uart = (volatile unsigned char *)0x10000000U;
static void pchr(uint32_t c) { *uart = (unsigned char)c; }
static void puts7(const char *s) { for (; *s; ++s) pchr((unsigned char)*s); pchr('\n'); }
static void putu(uint32_t x) {
  char b[12]; int i = 0;
  if (!x) pchr('0');
  while (x) { b[i++] = (char)('0' + (x % 10U)); x /= 10U; }
  while (i--) pchr(b[i]);
  pchr('\n');
}
static void fail(uint32_t code) { puts7("FAIL"); putu(code); asm volatile("csrrw x0,0x3ff,%0" : : "r"(1u) : "memory"); for (;;) pchr('x'); }
static void ok(void) { puts7("PASS"); asm volatile("csrrw x0,0x3ff,%0" : : "r"(1u) : "memory"); for (;;) pchr('x'); }
#endif
