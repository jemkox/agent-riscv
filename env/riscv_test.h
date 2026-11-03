#ifndef RVTEST_H
#define RVTEST_H
/* RV32I official test harness: pass means gp (x3) == 1 on XHALT halt. */
#define TESTNUM gp
#define RVTEST_RV32U
#define RVTEST_RV64U
#define RVTEST_RV64S
#define RVTEST_RV32U_BEGIN
#define RVTEST_RV32U_END
#define RVTEST_CODE_BEGIN .text; .globl _start; _start: li sp,0x2000
#define RVTEST_CODE_END
#define RVTEST_DATA_BEGIN .data
#define RVTEST_DATA_END
#define RVTEST_PASS li gp,1; csrrw x0,0x3ff,gp
#define RVTEST_FAIL slli gp,TESTNUM,1; ori gp,gp,1; csrrw x0,0x3ff,gp
#endif
