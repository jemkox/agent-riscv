// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vmem32.h for the primary calling header

#ifndef VERILATED_VMEM32___024ROOT_H_
#define VERILATED_VMEM32___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vmem32__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vmem32___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ probe3__DOT__clk;
    CData/*0:0*/ __Vtrigprevexpr___TOP__probe3__DOT__clk__0;
    CData/*0:0*/ __VactContinue;
    IData/*31:0*/ probe3__DOT__lwa;
    IData/*31:0*/ probe3__DOT__lwd;
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<IData/*31:0*/, 65536> probe3__DOT__M__DOT__ram;
    VlDelayScheduler __VdlySched;
    VlTriggerVec<2> __VactTriggered;
    VlTriggerVec<2> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vmem32__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vmem32___024root(Vmem32__Syms* symsp, const char* v__name);
    ~Vmem32___024root();
    VL_UNCOPYABLE(Vmem32___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
