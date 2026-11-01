// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vprobe2.h for the primary calling header

#ifndef VERILATED_VPROBE2___024ROOT_H_
#define VERILATED_VPROBE2___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vprobe2__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vprobe2___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ probe2__DOT__clk;
    CData/*0:0*/ __Vtrigprevexpr___TOP__probe2__DOT__clk__0;
    CData/*0:0*/ __VactContinue;
    IData/*31:0*/ probe2__DOT__a;
    IData/*31:0*/ __VactIterCount;
    VlDelayScheduler __VdlySched;
    VlTriggerVec<2> __VactTriggered;
    VlTriggerVec<2> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vprobe2__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vprobe2___024root(Vprobe2__Syms* symsp, const char* v__name);
    ~Vprobe2___024root();
    VL_UNCOPYABLE(Vprobe2___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
