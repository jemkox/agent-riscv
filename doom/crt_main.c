// doomgeneric entry point for the RV32 CPU testbench: attract-mode demo,
// no argv parsing (arguments are hardcoded; the WAD is memory-served).
#include "doomgeneric.h"

int main(void)
{
    static const char *args[] = { "doom", 0 };
    doomgeneric_Create(1, (char **)args);
    return 0;
}
