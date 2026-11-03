/* FreeRTOS demo on the rv32cpu pipeline: self-checking, prints FREERTOS PASS / FAIL on the UART.
 *  - producer/consumer: 50 numbers through a queue, order and sum checked
 *  - mutex: two tasks increment a shared counter and sleep while holding the mutex (forces real
 *    context switches inside the critical region); the final count proves mutual exclusion
 *  - preemption: two equal-priority tasks that never block must both make progress (time slicing
 *    by the tick interrupt)
 *  - software timer: auto-reload timer callbacks run from the timer service task */
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "timers.h"

#define N_ITEMS     50
#define N_MUTEX     20
#define UART        ( *( volatile uint8_t * ) 0x1FF00000u )

static QueueHandle_t xQueue;
static SemaphoreHandle_t xMutex, xDone;
static volatile uint32_t ulSum, ulOrderErrors, ulShared, ulSpinA, ulSpinB, ulTimerCalls;
volatile unsigned int ulSwitches;   /* counted by traceTASK_SWITCHED_IN in FreeRTOSConfig.h */

static void prvPuts( const char * s ) { while( *s ) UART = ( uint8_t ) *s++; }
static void prvPutu( uint32_t v )
{
    char b[ 11 ];
    int i = 0;
    do { b[ i++ ] = ( char ) ( '0' + v % 10 ); v /= 10; } while( v );
    while( i ) UART = ( uint8_t ) b[ --i ];
}
static void prvKV( const char * k, uint32_t v ) { prvPuts( k ); prvPutu( v ); prvPuts( "\n" ); }
static void prvHalt( void ) { __asm volatile ( "csrw 0x3ff, %0" :: "r" ( 1 ) ); for( ; ; ) { } }
static void prvFail( const char * why ) { prvPuts( "FREERTOS FAIL: " ); prvPuts( why ); prvPuts( "\n" ); prvHalt(); }

void vAssertFailed( const char * file, int line ) { prvPuts( file ); prvKV( ":", ( uint32_t ) line ); prvFail( "assert" ); }
void vApplicationStackOverflowHook( TaskHandle_t t, char * name ) { ( void ) t; prvPuts( name ); prvFail( " stack overflow" ); }
void vApplicationMallocFailedHook( void ) { prvFail( "out of heap" ); }
void vPortFatalTrap( uint32_t mcause, uint32_t mepc ) { prvKV( "mcause=", mcause ); prvKV( "mepc=", mepc ); prvFail( "unexpected trap" ); }

static void vProducer( void * p )
{
    ( void ) p;
    for( uint32_t i = 1; i <= N_ITEMS; i++ )
    {
        xQueueSend( xQueue, &i, portMAX_DELAY );
        if( i % 5 == 0 ) vTaskDelay( 1 );
    }
    vTaskDelete( NULL );
}

static void vConsumer( void * p )
{
    ( void ) p;
    for( uint32_t i = 1; i <= N_ITEMS; i++ )
    {
        uint32_t v;
        xQueueReceive( xQueue, &v, portMAX_DELAY );
        if( v != i ) ulOrderErrors++;
        ulSum += v;
    }
    xSemaphoreGive( xDone );
    vTaskDelete( NULL );
}

static void vMutexWorker( void * p )
{
    ( void ) p;
    for( int i = 0; i < N_MUTEX; i++ )
    {
        xSemaphoreTake( xMutex, portMAX_DELAY );
        uint32_t v = ulShared;
        vTaskDelay( 1 );          /* switched out while holding the mutex */
        ulShared = v + 1;
        xSemaphoreGive( xMutex );
    }
    xSemaphoreGive( xDone );
    vTaskDelete( NULL );
}

static void vSpin( void * p )
{
    volatile uint32_t * c = ( volatile uint32_t * ) p;
    for( ; ; ) ( *c )++;          /* never blocks: only the tick can switch it out */
}

static void vTimerCallback( TimerHandle_t t ) { ( void ) t; ulTimerCalls++; }

static void vCheck( void * p )
{
    ( void ) p;
    TickType_t t0 = xTaskGetTickCount();
    for( int i = 0; i < 3; i++ )
    {
        if( xSemaphoreTake( xDone, pdMS_TO_TICKS( 2000 ) ) != pdTRUE ) prvFail( "timeout waiting for workers" );
    }
    vTaskDelay( pdMS_TO_TICKS( 20 ) );   /* let the spinners and the timer run a little longer */
    TickType_t ticks = xTaskGetTickCount() - t0;

    prvKV( "ticks=", ticks );
    prvKV( "context switches=", ulSwitches );
    prvKV( "queue sum=", ulSum );
    prvKV( "queue order errors=", ulOrderErrors );
    prvKV( "mutex count=", ulShared );
    prvKV( "spinner A=", ulSpinA );
    prvKV( "spinner B=", ulSpinB );
    prvKV( "timer callbacks=", ulTimerCalls );
    if( ulSum != N_ITEMS * ( N_ITEMS + 1 ) / 2 || ulOrderErrors != 0 ) prvFail( "queue" );
    if( ulShared != 2 * N_MUTEX ) prvFail( "mutex" );
    if( ulSpinA == 0 || ulSpinB == 0 ) prvFail( "time slicing" );
    if( ulTimerCalls < 5 ) prvFail( "software timer" );
    prvPuts( "FREERTOS PASS\n" );
    prvHalt();
}

int main( void )
{
    prvPuts( "FreeRTOS " tskKERNEL_VERSION_NUMBER " on rv32cpu\n" );
    xQueue = xQueueCreate( 4, sizeof( uint32_t ) );
    xMutex = xSemaphoreCreateMutex();
    xDone = xSemaphoreCreateCounting( 3, 0 );
    TimerHandle_t tm = xTimerCreate( "tick5", 5, pdTRUE, NULL, vTimerCallback );
    if( !xQueue || !xMutex || !xDone || !tm ) prvFail( "create" );
    xTimerStart( tm, 0 );
    xTaskCreate( vProducer, "producer", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vConsumer, "consumer", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vMutexWorker, "mutex1", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vMutexWorker, "mutex2", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vSpin, "spinA", configMINIMAL_STACK_SIZE, ( void * ) &ulSpinA, 1, NULL );
    xTaskCreate( vSpin, "spinB", configMINIMAL_STACK_SIZE, ( void * ) &ulSpinB, 1, NULL );
    xTaskCreate( vCheck, "check", configMINIMAL_STACK_SIZE * 2, NULL, 3, NULL );
    vTaskStartScheduler();
    prvFail( "scheduler returned" );
    return 0;
}
