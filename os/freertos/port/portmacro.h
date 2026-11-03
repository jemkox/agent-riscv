/* FreeRTOS port for the rv32cpu pipeline (RV32IM, machine mode only).
 *
 * This CPU has a simplified trap model, so the stock GCC/RISC-V port does not fit:
 *  - mstatus bit 12 (MPP[1]) enables both traps and the timer interrupt; MIE/mie/mip do not exist.
 *    With it clear, ecall/ebreak/illegal instructions HALT the CPU instead of trapping.
 *  - A trap leaves that bit set, and mret does not change mstatus, so the handler disables
 *    interrupts itself (first instruction at mtvec, which the hardware never interrupts).
 *  - mtime is CSR 0x704 (an alias of mcycle) and mtimecmp is CSR 0x705, both 32-bit.
 * Hence: interrupts off/on = write 0 / 0x1800 to mstatus, and a yield cannot use ecall (FreeRTOS
 * yields inside critical sections). portYIELD() instead requests a switch by making the timer
 * interrupt due now (mtimecmp = 0), like PendSV on Cortex-M: it is taken as soon as interrupts
 * are enabled, which is immediately outside a critical section.
 */
#ifndef PORTMACRO_H
#define PORTMACRO_H

#include <stdint.h>

#define portSTACK_TYPE           uint32_t
#define portBASE_TYPE            int32_t
#define portUBASE_TYPE           uint32_t
#define portMAX_DELAY            ( TickType_t ) 0xffffffffUL

typedef portSTACK_TYPE   StackType_t;
typedef portBASE_TYPE    BaseType_t;
typedef portUBASE_TYPE   UBaseType_t;
typedef portUBASE_TYPE   TickType_t;

#define portCHAR                   char
#define portFLOAT                  float
#define portDOUBLE                 double
#define portLONG                   long
#define portSHORT                  short
#define portTICK_TYPE_IS_ATOMIC    1
#define portSTACK_GROWTH           ( -1 )
#define portTICK_PERIOD_MS         ( ( TickType_t ) 1000 / configTICK_RATE_HZ )
#define portBYTE_ALIGNMENT         16

#define portMSTATUS_TRAPS_ON       0x1800u   /* bit 12 enables traps + timer; bit 11 follows it */
#define portCSR_MTIME              0x704
#define portCSR_MTIMECMP           0x705

extern void vTaskSwitchContext( void );
extern void vPortYield( void );
#define portYIELD()                              vPortYield()
#define portEND_SWITCHING_ISR( xSwitchRequired ) do { if( ( xSwitchRequired ) != pdFALSE ) vPortYield(); } while( 0 )
#define portYIELD_FROM_ISR( x )                  portEND_SWITCHING_ISR( x )

#define portCRITICAL_NESTING_IN_TCB    0
#define portDISABLE_INTERRUPTS()       __asm volatile ( "csrw mstatus, zero" ::: "memory" )
#define portENABLE_INTERRUPTS()        __asm volatile ( "csrw mstatus, %0" :: "r" ( portMSTATUS_TRAPS_ON ) : "memory" )

/* Context switches happen only from the timer trap, i.e. only while interrupts are enabled,
 * so every task is switched out at nesting 0 and one global count is enough. */
extern volatile UBaseType_t uxCriticalNesting;
#define portENTER_CRITICAL()     do { portDISABLE_INTERRUPTS(); uxCriticalNesting++; } while( 0 )
#define portEXIT_CRITICAL()      do { if( --uxCriticalNesting == 0 ) portENABLE_INTERRUPTS(); } while( 0 )

#define configUSE_PORT_OPTIMISED_TASK_SELECTION    0

#define portTASK_FUNCTION_PROTO( vFunction, pvParameters )    void vFunction( void * pvParameters )
#define portTASK_FUNCTION( vFunction, pvParameters )          void vFunction( void * pvParameters )
#define portNOP()               __asm volatile ( "nop" )
#define portINLINE              __inline
#ifndef portFORCE_INLINE
    #define portFORCE_INLINE    inline __attribute__( ( always_inline ) )
#endif
#define portMEMORY_BARRIER()    __asm volatile ( "" ::: "memory" )

#endif /* PORTMACRO_H */
