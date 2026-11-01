#include "m7common.h"
#include <stdint.h>
#define N 16
static uint32_t A[N*N], B[N*N], C[N*N];
int main(void) {
  for (int i=0;i<N;i++) for (int j=0;j<N;j++) { A[i*N+j]=(uint32_t)(i+j); B[i*N+j]=(uint32_t)(i*j+1); }
  for (int i=0;i<N;i++) for (int j=0;j<N;j++) { uint32_t s=0; for (int k=0;k<N;k++) s += A[i*N+k] * B[k*N+j]; C[i*N+j]=s; }
  uint32_t got=0;
  for (int i=0;i<N;i++) for (int j=0;j<N;j++) {
    uint32_t exp = (uint32_t)i * ((uint32_t)j*120U + 16U) + (uint32_t)j*1240U + 120U;
    if (C[i*N+j] != exp) fail(2U);
    got = got*131U + C[i*N+j];
  }
  puts7("MATMUL PASS"); putu(got); ok(); return 0;
}
