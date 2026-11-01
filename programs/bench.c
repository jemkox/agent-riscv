#include "m7common.h"
#include <stdint.h>
static uint32_t x, y, z, k;
static void reset(void) { x = 0; y = 0; z = 0; k = 0; }
static uint32_t bench(uint32_t runs) {
  reset();
  for (uint32_t r = 0; r < runs; ++r) {
    for (uint32_t i = 0; i < 100U; ++i) {
      x = x + i;
      y = y ^ (x << 1);
      z = z + y;
      if (z & 1U) { k = k + 1U; } else { k = k + (z >> 3); }
      while (z > y) z -= (y + 1U);
      for (uint32_t j = 0; j < 5U; ++j) x ^= (j * y);
    }
  }
  return x ^ y ^ z ^ k;
}
int main(void) {
  uint32_t got = bench(25U);
  uint32_t exp = bench(25U);
  if (got != exp) fail(3U);
  puts7("BENCH PASS"); putu(got); ok(); return 0;
}
