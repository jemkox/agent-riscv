// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vprobe4.h for the primary calling header

#ifndef VERILATED_VPROBE4___024ROOT_H_
#define VERILATED_VPROBE4___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vprobe4__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vprobe4___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ probe4__DOT__clk;
    CData/*0:0*/ __Vtrigprevexpr___TOP__probe4__DOT__clk__0;
    CData/*0:0*/ __VactContinue;
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<IData/*31:0*/, 2> probe4__DOT__ram;
    VlDelayScheduler __VdlySched;
    VlTriggerVec<2> __VactTriggered;
    VlTriggerVec<2> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vprobe4__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vprobe4___024root(Vprobe4__Syms* symsp, const char* v__name);
    ~Vprobe4___024root();
    VL_UNCOPYABLE(Vprobe4___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
