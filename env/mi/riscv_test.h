#ifndef RISCV_TEST_H
#define RISCV_TEST_H
#include "encoding.h"

#define RVTEST_RV32M
#define RVTEST_RV64M RVTEST_RV32M
#define RVTEST_RV64S RVTEST_RV32M
#define TESTNUM gp
#define RVTEST_DATA_BEGIN
#define RVTEST_DATA_END

#define RVTEST_CODE_BEGIN \
  .text; \
  .globl _start; \
_start: \
  li sp,0x2000; \
  li gp,0; \
  la t0,trap_vector; csrw mtvec,t0; \
  li t0,MSTATUS_MPP; csrs mstatus,t0; \
  j code_begin; \
  .align 2; \
  .weak mtvec_handler; \
trap_vector: \
  la t5,mtvec_handler; \
  beqz t5,other_exception; \
  jr t5; \
  .align 2; \
other_exception: \
  ori gp,gp,1337; \
  li t0,1; csrw 0x3ff,t0; \
  ebreak; \
  .align 2; \
code_begin:

#define RVTEST_CODE_END ebreak

#define RVTEST_PASS \
  li gp,1; \
  li t0,1; \
  csrw 0x3ff,t0

#define RVTEST_FAIL \
  ori gp,gp,1; \
  li t0,1; \
  csrw 0x3ff,t0

#define mret li x15,0x1800; csrs mstatus,x15; csrr x15,mepc; jalr x0,x15,0

#endif
