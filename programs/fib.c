#include "m7common.h"
#include <stdint.h>
static uint32_t fib(uint32_t n) { if (n < 2U) return n; return fib(n-1U)+fib(n-2U); }
int main(void) { uint32_t r=fib(20U); if (r != 6765U) fail(r); puts7("FIB PASS"); putu(r); ok(); return 0; }
