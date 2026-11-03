/* FreeRTOS port for the rv32cpu pipeline: scheduler start, tick, yield. See portmacro.h for the
 * CPU's trap model and portasm.S for the context save/restore. */
#include "FreeRTOS.h"
#include "task.h"

/* Timer cycles per tick. mtime runs from 0 to TICK_CYCLES and is pulled back by TICK_CYCLES at each
 * tick, so the 32-bit compare against mtimecmp never meets a wrap-around. */
#define TICK_CYCLES     ( configCPU_CLOCK_HZ / configTICK_RATE_HZ )
/* A tick this close to due is taken now: the handler exit runs with interrupts on for a few
 * instructions and must not be interrupted itself. */
#define TICK_MARGIN     256u
#define MCAUSE_TIMER    0x80000007u

volatile UBaseType_t uxCriticalNesting = 0xaaaaaaaa;   /* 0 from xPortStartScheduler on */
static volatile uint32_t ulYieldPending = 0;

extern void vPortStartFirstTask( void );   /* portasm.S */
extern void vPortTrapEntry( void );        /* portasm.S */
extern void vPortFatalTrap( uint32_t mcause, uint32_t mepc );   /* application: report and halt */

static inline uint32_t prvReadMtime( void )
{
    uint32_t t;
    __asm volatile ( "csrr %0, 0x704" : "=r" ( t ) );
    return t;
}

static inline void prvWriteMtime( uint32_t t ) { __asm volatile ( "csrw 0x704, %0" :: "r" ( t ) ); }
static inline void prvWriteMtimecmp( uint32_t t ) { __asm volatile ( "csrw 0x705, %0" :: "r" ( t ) : "memory" ); }

static void prvTaskExitError( void )
{
    /* A task function returned; FreeRTOS tasks must delete themselves instead. */
    configASSERT( 0 );
    for( ; ; ) { }
}

/* Called from portasm.S with interrupts off, on the ISR stack, after the current task's context
 * was saved. On return portasm.S restores pxCurrentTCB's context. */
void vPortTrapHandler( uint32_t mcause, uint32_t mepc )
{
    uint32_t now;

    if( mcause != MCAUSE_TIMER )
    {
        vPortFatalTrap( mcause, mepc );
    }

    if( ulYieldPending != 0 )   /* portYIELD() made the timer due */
    {
        ulYieldPending = 0;
        vTaskSwitchContext();
    }

    while( ( now = prvReadMtime() ) >= TICK_CYCLES - TICK_MARGIN )
    {
        prvWriteMtime( now >= TICK_CYCLES ? now - TICK_CYCLES : 0 );
        if( xTaskIncrementTick() != pdFALSE )
        {
            vTaskSwitchContext();
        }
    }

    prvWriteMtimecmp( TICK_CYCLES );
}

void vPortYield( void )
{
    ulYieldPending = 1;
    prvWriteMtimecmp( 0 );   /* timer due now: taken at once, or when the critical section ends */
}

/* Initial frame, matching portasm.S: word 0 = mepc, word i = register xi (x2 sp, x3 gp, x4 tp
 * are not saved). 32 words keep the 16-byte alignment. */
StackType_t * pxPortInitialiseStack( StackType_t * pxTopOfStack, TaskFunction_t pxCode, void * pvParameters )
{
    int i;

    pxTopOfStack -= 32;
    for( i = 0; i < 32; i++ )
    {
        pxTopOfStack[ i ] = 0;
    }
    pxTopOfStack[ 0 ] = ( StackType_t ) pxCode;              /* mepc: where the task starts */
    pxTopOfStack[ 1 ] = ( StackType_t ) prvTaskExitError;    /* ra */
    pxTopOfStack[ 10 ] = ( StackType_t ) pvParameters;       /* a0 */
    return pxTopOfStack;
}

BaseType_t xPortStartScheduler( void )
{
    __asm volatile ( "csrw mtvec, %0" :: "r" ( vPortTrapEntry ) );
    uxCriticalNesting = 0;
    prvWriteMtime( 0 );
    prvWriteMtimecmp( TICK_CYCLES );
    vPortStartFirstTask();   /* does not return */
    return pdFAIL;
}

void vPortEndScheduler( void )
{
    for( ; ; ) { }
}
