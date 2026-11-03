/* FreeRTOS configuration for the rv32cpu demo (simulation, DOOM_BIG memory map). */
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#define configCPU_CLOCK_HZ                      13000000   /* the iCE40 UP5K build's clock */
#define configTICK_RATE_HZ                      1000       /* 13,000 cycles per tick */
#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                  1
#define configMAX_PRIORITIES                    5
#define configMINIMAL_STACK_SIZE                256        /* words */
#define configMAX_TASK_NAME_LEN                 12
#define configTICK_TYPE_WIDTH_IN_BITS           TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_MUTEXES                       1
#define configUSE_COUNTING_SEMAPHORES           1
#define configQUEUE_REGISTRY_SIZE               0
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configCHECK_FOR_STACK_OVERFLOW          2
#define configUSE_MALLOC_FAILED_HOOK            1

#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configSUPPORT_STATIC_ALLOCATION         0
#define configTOTAL_HEAP_SIZE                   ( 64 * 1024 )

#define configUSE_TIMERS                        1
#define configTIMER_TASK_PRIORITY               ( configMAX_PRIORITIES - 1 )
#define configTIMER_QUEUE_LENGTH                8
#define configTIMER_TASK_STACK_DEPTH            configMINIMAL_STACK_SIZE

/* Stock FreeRTOS RISC-V port (portable/GCC/RISC-V) on our CLINT at 0x0200_0000:
   mtime 64-bit at +0x808 (lo,hi consecutive), mtimecmp 64-bit at +0x800. */
#define configMTIME_BASE_ADDRESS                ( 0x02000808 )
#define configMTIMECMP_BASE_ADDRESS             ( 0x02000800 )

#define INCLUDE_vTaskDelay                      1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_xTaskGetTickCount               1
#define INCLUDE_uxTaskGetStackHighWaterMark     1

extern volatile unsigned int ulSwitches;
#define traceTASK_SWITCHED_IN()    ( ulSwitches++ )

extern void vAssertFailed( const char * file, int line );
#define configASSERT( x )    do { if( !( x ) ) vAssertFailed( __FILE__, __LINE__ ); } while( 0 )

#endif /* FREERTOS_CONFIG_H */
