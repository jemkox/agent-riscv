#include "m7common.h"
#include <stdint.h>
static uint32_t a[1000];
int main(void) {
  uint32_t seed = 12345U;
  for (int i=0;i<1000;i++){ seed = seed*1664525U + 1013904223U; a[i]=seed; }
  for (int i=1;i<1000;i++) { uint32_t v=a[i], j=i-1; while (((int)j>=0) && (a[(int)j] > v)) { a[(int)j+1]=a[(int)j]; --j; } a[(int)j+1]=v; }
  uint32_t sum=0, prev=0;
  for (int i=0;i<1000;i++) { if (i && prev > a[i]) fail(1U); prev=a[i]; sum = sum*31U + prev; }
  puts7("SORT PASS"); putu(sum); ok(); return 0;
}
