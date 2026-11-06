#ifndef RISCV_TEST_H
#define RISCV_TEST_H
#include "encoding.h"

#define RVTEST_RV32M
#define RVTEST_RV64M RVTEST_RV32M
#define RVTEST_RV32S
#define RVTEST_RV64S RVTEST_RV32S
#define TESTNUM gp
#define RVTEST_DATA_BEGIN
#define RVTEST_DATA_END

// Supervisor-mode sources run with -D__MACHINE_MODE: the test bodies map the
// s* names to their m* equivalents (stvec->mtvec, sepc->mepc, sret->mret, ...),
// which this machine-mode M+U CPU already implements.  The begin macro drops the
// CPU into machine mode (MSTATUS_MPP in mstatus); the tests then clear MPP and
// use mret to reach U, exactly as the mapped machine-mode scall/csr tests expect.
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
  .weak stvec_handler; \
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
  li gp,1; \
  slli gp,gp,1; \
  ori gp,gp,1; \
  li t0,1; \
  csrw 0x3ff,t0

#endif
