// doomgeneric port layer for the RV32IM CPU testbench (M10c/M10d).
// Frame buffer lives in normal RAM (DG_ScreenBuffer from malloc).
// DG_DrawFrame stores a magic word to FRAME_ADDR; the Verilated C++ main
// watches the EX/MEM store port and dumps the framebuffer as a PPM.
#include <stdint.h>
#include <stddef.h>
#include "doomgeneric.h"

#define UART_ADDR   0x1FF00000u
#define FRAME_ADDR  0x1FF00004u
#define KEY_ADDR    0x1FF00008u   // MMIO key FIFO (cache32 KEY_ADDR)

// M10f key events: the Verilated play testbench pushes (pressed<<16)|keycode
// words into a FIFO and feeds the head via the model's key_in input; the
// cache32 pulses key_hit when the consuming load happens (C++ pops).
// A load here returns 0 when the FIFO is empty.
int DG_GetKey(int *pressed, unsigned char *doomKey)
{
    volatile uint32_t *keyreg = (volatile uint32_t *)KEY_ADDR;
    uint32_t v = *keyreg;
    if (!v)
        return 0;
    *doomKey = (unsigned char)(v & 0xFFu);
    *pressed = (int)((v >> 16) & 1u);
    return 1;
}

static volatile uint32_t ms_now;

void DG_Init(void) {}

void DG_SetWindowTitle(const char *title) { (void)title; }

// Notify the testbench that one frame was drawn (store -> MMIO-ish address).
void DG_DrawFrame(void)
{
    volatile uint32_t *flag = (volatile uint32_t *)FRAME_ADDR;
    *flag = 0x46524d31u; // "FRM1"
}

void DG_SleepMs(uint32_t ms)
{
    ms_now += (ms == 0) ? 1u : ms;
}

uint32_t DG_GetTicksMs(void)
{
    ms_now += 2u;
    return ms_now;
}

int main(int argc, char **argv)
{
    (void)argc; (void)argv;
    /* Start like "doom -iwad doom1.wad": never let the IWAD search guess (it would pick doom2.wad). */
    static char *args[] = { "doom", "-iwad", "doom1.wad", 0 };
    doomgeneric_Create(3, args);
    for (;;)
        doomgeneric_Tick();   /* doomgeneric_Create only initializes; the game runs in Tick */
    return 0;
}
